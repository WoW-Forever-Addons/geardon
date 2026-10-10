local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) What makes an arrow smarter, and what the tooltips
-- add: the weapon types you use, your best armour type, your class's main
-- stats, the stat split of an item, set pieces you would lose and the BoE
-- mark. Only what the client tells at runtime; the few fixed IDs below are
-- named with their source.
---------------------------------------------------------------------------
local stats = { statsApi = 0, statsTooltip = 0, statsNone = 0, setChecks = 0, boeChecks = 0 }
ns.upgradeStats = stats

local playerClass
local function PlayerClass()
  if playerClass then return playerClass end
  local _, class = ns.Results(UnitClass, "player")
  playerClass = ns.Str(class) -- a character's class never changes
  return playerClass
end
ns.PlayerClass = PlayerClass

---------------------------------------------------------------------------
-- Item classes (Enum.ItemClass / Enum.ItemWeaponSubclass / Enum.ItemArmorSubclass
-- of the client; fallback numbers from warcraft.wiki.gg/wiki/ItemType, the same
-- as Classic's ItemSubClass table).
---------------------------------------------------------------------------
local function EnumValue(enumName, key, fallback)
  local e = Enum and Enum[enumName]
  local v = type(e) == "table" and ns.Num(e[key])
  return v or fallback
end

local W = {}
local A = {}
local function ResolveEnums()
  W.bows = EnumValue("ItemWeaponSubclass", "Bows", 2)
  W.guns = EnumValue("ItemWeaponSubclass", "Guns", 3)
  W.thrown = EnumValue("ItemWeaponSubclass", "Thrown", 16)
  W.crossbow = EnumValue("ItemWeaponSubclass", "Crossbow", 18)
  W.wand = EnumValue("ItemWeaponSubclass", "Wand", 19)
  A.cloth = EnumValue("ItemArmorSubclass", "Cloth", 1)
  A.leather = EnumValue("ItemArmorSubclass", "Leather", 2)
  A.mail = EnumValue("ItemArmorSubclass", "Mail", 3)
  A.plate = EnumValue("ItemArmorSubclass", "Plate", 4)
end
ResolveEnums()

local WEAPON, ARMOR = 2, 4

-- Ranged weapons of one family replace each other: bows, guns and crossbows
-- (all "shoot"), thrown weapons, wands, relics (librams, idols, totems).
local function RangedFamily(info)
  if not info then return nil end
  if info.equipLoc == "INVTYPE_RELIC" then return "relic" end
  if info.classID ~= WEAPON then return nil end
  local s = info.subclassID
  if s == W.bows or s == W.guns or s == W.crossbow then return "shoot" end
  if s == W.thrown then return "thrown" end
  if s == W.wand then return "wand" end
  return nil
end
ns.RangedFamily = RangedFamily

-- Kind of a hand item: weapon subclass ("w7"), or the off-hand armour kind
-- (shield, held in off hand) by its equip location.
local function HandKind(classID, subclassID, equipLoc)
  if classID == WEAPON and subclassID then return "w" .. subclassID end
  if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then return equipLoc end
  return nil
end

-- (a) Weapon types you actually use. The slot the item is compared with
-- holds an item: the new one must be of a kind you wear in your hands (or,
-- for the ranged slot, of the same ranged family). An empty slot takes
-- anything you can wear. Option arrowWeaponMatch (on): off = any weapon.
function ns.WeaponTypeOK(info, slot)
  if ns.db and ns.db.arrowWeaponMatch == false then return true end
  local eq = ns.Equipped()
  if slot == "RangedSlot" or ns.INVTYPE[info.equipLoc or ""] == "RANGED" then
    local cur = eq.RangedSlot
    if not cur then return true end
    local mine, theirs = RangedFamily(cur), RangedFamily(info)
    return mine == nil or mine == theirs
  end
  if slot ~= "MainHandSlot" and slot ~= "SecondaryHandSlot" then return true end
  local mh, oh = eq.MainHandSlot, eq.SecondaryHandSlot
  local cur = eq[slot]
  if info.equipLoc == "INVTYPE_2HWEAPON" and not mh then return true end
  if not cur then return true end
  local kind = HandKind(info.classID, info.subclassID, info.equipLoc)
  if not kind then return true end
  local a = mh and HandKind(mh.classID, mh.subclassID, mh.equipLoc)
  local b = oh and HandKind(oh.classID, oh.subclassID, oh.equipLoc)
  if a == nil and b == nil then return true end -- what you wear is not known yet: no guess
  return kind == a or kind == b
end

---------------------------------------------------------------------------
-- (b) Your best armour type. The proficiency spells (Wowhead Classic, checked
-- 10.10.2026: spell=750 "Plate Mail", spell=8737 "Mail", spell=9077 "Leather";
-- Warriors and Paladins learn Plate Mail at 40, Hunters and Shamans Mail at 40)
-- and the best armour you wear now; the higher of both. Cloaks are cloth for
-- everyone and are left out. Option arrowBestArmor (off): on = an armour piece
-- of a lower type than your best gets no arrow.
---------------------------------------------------------------------------
local PROFICIENCY = { { 750, "plate" }, { 8737, "mail" }, { 9077, "leather" } }
local ARMOR_SLOTS = { "HeadSlot", "ShoulderSlot", "ChestSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot" }
local bestCache, bestVer

local function Knows(spellID)
  local fn = rawget(_G, "IsPlayerSpell") or rawget(_G, "IsSpellKnown")
  if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" and type(fn) ~= "function" then fn = C_SpellBook.IsSpellKnown end
  return ns.Value(fn, spellID) == true
end

local function IsBodyArmor(classID, subclassID, equipLoc)
  if classID ~= ARMOR or equipLoc == "INVTYPE_CLOAK" then return false end
  return subclassID == A.cloth or subclassID == A.leather or subclassID == A.mail or subclassID == A.plate
end

function ns.BestArmorSubclass()
  if bestVer == ns.version then return bestCache end
  local best
  for _, p in ipairs(PROFICIENCY) do
    if Knows(p[1]) then
      local v = A[p[2]]
      if not best or v > best then best = v end
    end
  end
  local eq = ns.Equipped()
  for _, name in ipairs(ARMOR_SLOTS) do
    local e = eq[name]
    if e and IsBodyArmor(e.classID, e.subclassID, e.equipLoc) and (not best or e.subclassID > best) then best = e.subclassID end
  end
  bestCache, bestVer = best, ns.version
  return best
end

function ns.ArmorTypeOK(info)
  if not (ns.db and ns.db.arrowBestArmor) then return true end
  if not IsBodyArmor(info.classID, info.subclassID, info.equipLoc) then return true end
  local best = ns.BestArmorSubclass()
  return not best or info.subclassID >= best
end

---------------------------------------------------------------------------
-- (3) Stats of an item: what the client computes (C_Item.GetItemStats or
-- GetItemStats), else the stat lines of the tooltip data. Only the five
-- primary stats are read. Returns { STR = n, ... } (may be empty: the item has
-- no primary stat) or nil (unknown).
---------------------------------------------------------------------------
local PRIMARY = {
  { "STR", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STRENGTH", "Strength" },
  { "AGI", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_AGILITY", "Agility" },
  { "STA", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STAMINA", "Stamina" },
  { "INT", "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_INTELLECT", "Intellect" },
  { "SPI", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_SPIRIT", "Spirit" },
}
ns.PRIMARY_STATS = PRIMARY

function ns.StatName(key)
  for _, p in ipairs(PRIMARY) do
    if p[1] == key then return ns.Str(rawget(_G, p[2])) or L[p[4]] end
  end
  return key
end

-- A table (empty: the game knows the item and it has no primary stat), or
-- nil when no stats function answers.
local function FromApi(link)
  local t
  if C_Item and type(C_Item.GetItemStats) == "function" then t = ns.Call(C_Item.GetItemStats, link) end
  if type(t) ~= "table" and type(rawget(_G, "GetItemStats")) == "function" then
    t = ns.Call(rawget(_G, "GetItemStats"), link)
  end
  if type(t) ~= "table" or not ns.Usable(t) then return nil end -- a secret value counts as missing
  local out = {}
  for _, p in ipairs(PRIMARY) do
    local v = ns.Num(t[p[2]])
    if v and v > 0 then out[p[1]] = v end
  end
  return out
end

-- "%c%s Agility" (ITEM_MOD_AGILITY) as a pattern for "+12 Agility".
local patterns
local function Patterns()
  if patterns then return patterns end
  patterns = {}
  for _, p in ipairs(PRIMARY) do
    local fmt = ns.Str(rawget(_G, p[3]))
    if fmt then
      local pat = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
      pat = pat:gsub("%%c", "[+]?"):gsub("%%d", "(%%d+)"):gsub("%%s", "(%%d+)")
      patterns[#patterns + 1] = { p[1], "^" .. pat .. "$" }
    end
  end
  return patterns
end

local function FromLines(lines)
  if type(lines) ~= "table" or not ns.Usable(lines) then return nil end
  local out, seen = {}, false
  for _, line in ipairs(lines) do
    local text = type(line) == "table" and ns.Str(line.leftText)
    if text then
      for _, p in ipairs(Patterns()) do
        local n = tonumber(text:match(p[2]))
        if n and n > 0 then out[p[1]] = (out[p[1]] or 0) + n seen = true end
      end
    end
  end
  return seen and out or nil
end

-- info: ns.ItemInfo table (the result is kept in it: the item is loaded when
-- ItemInfo answers, so its stats do not change); lines: tooltip data lines
-- (optional, used when the stats functions give nothing).
function ns.ItemStats(info, lines)
  if type(info) ~= "table" or not info.link then return nil end
  local s = info.stats
  if s == nil then
    s = FromApi(info.link)
    if s then stats.statsApi = stats.statsApi + 1 else stats.statsNone = stats.statsNone + 1 end
    info.stats = s or false
  end
  if (not s or next(s) == nil) and lines then
    local t = FromLines(lines)
    if t then
      stats.statsTooltip = stats.statsTooltip + 1
      info.stats = t
      return t
    end
  end
  return s or nil
end

-- "Agility 60% · Stamina 40%": shares of the primary stats, whole percent,
-- adding up to 100 (largest remainder). nil without a primary stat.
function ns.StatSplitText(s)
  if type(s) ~= "table" then return nil end
  local total, parts = 0, {}
  for _, p in ipairs(PRIMARY) do
    local v = s[p[1]]
    if v then total = total + v parts[#parts + 1] = { key = p[1], v = v } end
  end
  if total <= 0 then return nil end
  local sum = 0
  for _, e in ipairs(parts) do
    local exact = e.v * 100 / total
    e.pct, e.rest = math.floor(exact), exact - math.floor(exact)
    sum = sum + e.pct
  end
  local order = {}
  for i, e in ipairs(parts) do order[i] = e end
  table.sort(order, function(a, b) return a.rest > b.rest end)
  for i = 1, 100 - sum do order[(i - 1) % #order + 1].pct = order[(i - 1) % #order + 1].pct + 1 end
  table.sort(parts, function(a, b) if a.pct ~= b.pct then return a.pct > b.pct end return a.key < b.key end)
  local out = {}
  for _, e in ipairs(parts) do out[#out + 1] = L["%s %d%%"]:format(ns.StatName(e.key), e.pct) end
  return table.concat(out, " · ")
end

---------------------------------------------------------------------------
-- Main stats per class, chosen wide on purpose (a stat any spec of the class
-- uses counts): the arrow is only taken away from items whose stats no spec
-- of your class wants. Stamina counts for the classes that tank or fight in
-- melee. Items whose stats are unknown, or that have no primary stat at all,
-- keep their arrow. Option arrowMainStats (on).
---------------------------------------------------------------------------
local MAIN = {
  WARRIOR = { STR = true, AGI = true, STA = true },
  ROGUE = { AGI = true, STR = true, STA = true },
  HUNTER = { AGI = true, INT = true, STA = true },
  PALADIN = { STR = true, INT = true, STA = true, SPI = true },
  SHAMAN = { INT = true, STR = true, AGI = true, STA = true, SPI = true },
  DRUID = { INT = true, AGI = true, STR = true, STA = true, SPI = true },
  MAGE = { INT = true, SPI = true, STA = true },
  PRIEST = { INT = true, SPI = true, STA = true },
  WARLOCK = { INT = true, SPI = true, STA = true },
}
ns.MAIN_STATS = MAIN

-- true: has one of your main stats (or nothing to judge); false: has primary stats, none of yours.
function ns.MainStatsOK(info)
  if not (ns.db and ns.db.arrowMainStats ~= false) then return true end
  local main = MAIN[PlayerClass() or ""]
  if not main then return true end
  local s = ns.ItemStats(info)
  if not s or next(s) == nil then return true end
  for key in pairs(s) do
    if main[key] then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- (9) Set pieces. An equipped item with a set ID is "at stake" when its set
-- gives you a bonus now: the game's tooltip of that item shows active set
-- bonuses as "Set: ..." (ITEM_SET_BONUS) and inactive ones as "(2) Set: ..."
-- (ITEM_SET_BONUS_GRAY). Without tooltip data: at least two pieces of that set
-- are worn (a bonus may be active). Read once per gear change.
---------------------------------------------------------------------------
local setState, setVer = {}, nil

local function Prefix(global)
  local fmt = ns.Str(rawget(_G, global))
  if not fmt then return nil end
  return (fmt:match("^(.-)%%") or fmt)
end

local function ActiveBonus(slotID)
  if not (C_TooltipInfo and type(C_TooltipInfo.GetInventoryItem) == "function") then return nil end
  local data = ns.Value(C_TooltipInfo.GetInventoryItem, "player", slotID)
  local lines = type(data) == "table" and data.lines
  if type(lines) ~= "table" or not ns.Usable(lines) then return nil end
  local active, grey = Prefix("ITEM_SET_BONUS"), Prefix("ITEM_SET_BONUS_GRAY")
  if not active or active == "" then return nil end
  local found = false
  for _, line in ipairs(lines) do
    local text = type(line) == "table" and ns.Str(line.leftText)
    if text then
      if text:sub(1, #active) == active and not (grey and grey ~= "" and text:sub(1, #grey) == grey) then return true end
      if grey and grey ~= "" and text:sub(1, #grey) == grey then found = true end
    end
  end
  if found then return false end -- only inactive bonuses ("(2) Set: ...")
  return nil
end

local function ReadSets()
  wipe(setState)
  local eq = ns.Equipped()
  local count = {}
  for _, e in pairs(eq) do
    if e.setID then count[e.setID] = (count[e.setID] or 0) + 1 end
  end
  for name, e in pairs(eq) do
    if e.setID then
      stats.setChecks = stats.setChecks + 1
      local active = ActiveBonus(ns.SLOT[name])
      if active == nil then active = count[e.setID] >= 2 end
      setState[name] = active and e.setID or false
    end
  end
  setVer = ns.version
end

-- The set ID when the item in that slot belongs to a set whose bonus you have
-- now (and the new item is not of the same set), else nil.
function ns.SetPieceAtStake(slot, info)
  if setVer ~= ns.version then ReadSets() end
  local id = slot and setState[slot]
  if not id then return nil end
  if info and info.setID == id then return nil end
  return id
end

function ns.SetPieceSlots()
  if setVer ~= ns.version then ReadSets() end
  return setState
end

---------------------------------------------------------------------------
-- (7) Bind on equip, not yet bound: GetItemInfo's bind type 2 (LE_ITEM_BIND_ON_EQUIP),
-- and the item in that bag slot is not bound (C_Item.IsBound, else the
-- tooltip data: ITEM_SOULBOUND). Unknown: no mark.
---------------------------------------------------------------------------
local BIND_ON_EQUIP = rawget(_G, "LE_ITEM_BIND_ON_EQUIP") or 2

function ns.IsBoE(info, bag, slot)
  if type(info) ~= "table" or info.bindType ~= (ns.Num(BIND_ON_EQUIP) or 2) then return false end
  if not (bag and slot) then return false end
  stats.boeChecks = stats.boeChecks + 1
  if ItemLocation and type(ItemLocation.CreateFromBagAndSlot) == "function" and C_Item and type(C_Item.IsBound) == "function" then
    local ok, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if ok and loc then
      local bound = ns.Value(C_Item.IsBound, loc)
      if bound == true then return false end
      if bound == false then return true end
    end
  end
  if C_TooltipInfo and type(C_TooltipInfo.GetBagItem) == "function" then
    local data = ns.Value(C_TooltipInfo.GetBagItem, bag, slot)
    local lines = type(data) == "table" and data.lines
    if type(lines) == "table" and ns.Usable(lines) then
      local soul, boe = ns.Str(rawget(_G, "ITEM_SOULBOUND")), ns.Str(rawget(_G, "ITEM_BIND_ON_EQUIP"))
      local saw = false
      for _, line in ipairs(lines) do
        local text = type(line) == "table" and ns.Str(line.leftText)
        if text and soul and text == soul then return false end
        if text and boe and text == boe then saw = true end
      end
      return saw
    end
  end
  return false
end

ns.OnInit(ResolveEnums)
