local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) Dungeons for your level, for "where to get better".
-- Honest on purpose: these are dungeons that fit your level, not a promise
-- that an item for a given slot drops there (Geardon has no loot tables).
--
-- Level ranges: Questdon's when Questdon is loaded and its API offers them
-- (QuestdonAPI.DungeonLevelRange(instanceID) -> min, max; API version 1 has no
-- such function yet, so today this table is used). The table is a copy of
-- Questdon's Data/Dungeon_Levels.lua (1.3.5, 10.10.2026), same values, same
-- source: warcrafttavern.com/forever/guides/dungeons, fetched 10.10.2026
-- (Scarlet Monastery as one dungeon, its wings 30-38, 33-41, 36-44, 38-46).
-- Names: the client's name of the dungeon map (C_Map.GetMapInfo with the map
-- IDs of All The Things' Forever data, as in Questdon), else the English name.
-- Raids are left out.
-- [instanceID] = { min, max, uiMapID or false, English name }
---------------------------------------------------------------------------
local DUNGEONS = {
  [226] = { 13, 20, 213, "Ragefire Chasm" },
  [3065] = { 13, 20, false, "Hall of Thanes" },
  [2999] = { 15, 22, false, "Ruins of Lordaeron" },
  [240] = { 15, 24, 279, "Wailing Caverns" },
  [63] = { 17, 26, 291, "The Deadmines" },
  [64] = { 20, 30, 310, "Shadowfang Keep" },
  [227] = { 24, 32, 221, "Blackfathom Deeps" },
  [238] = { 24, 32, 225, "The Stockade" },
  [2998] = { 26, 33, false, "Excavation Site: Wetlands" },
  [2959] = { 28, 33, false, "City of Dalaran" },
  [231] = { 29, 38, 226, "Gnomeregan" },
  [234] = { 29, 38, 301, "Razorfen Kraul" },
  [316] = { 30, 46, 435, "Scarlet Monastery" },
  [233] = { 37, 46, 300, "Razorfen Downs" },
  [239] = { 41, 51, 230, "Uldaman" },
  [241] = { 40, 47, 219, "Zul'Farrak" },
  [232] = { 45, 51, 280, "Maraudon" },
  [237] = { 50, 55, 220, "The Temple of Atal'Hakkar" },
  [228] = { 52, 60, 242, "Blackrock Depths" },
  [229] = { 57, 60, 250, "Blackrock Spire" },
  [230] = { 58, 60, 234, "Dire Maul" },
  [236] = { 58, 60, 317, "Stratholme" },
}
ns.DUNGEON_TABLE = DUNGEONS

local stats = { source = "table" }
ns.dungeonStats = stats

local function DungeonName(inst)
  local d = DUNGEONS[inst]
  if not d then return tostring(inst) end
  if d[3] and C_Map and type(C_Map.GetMapInfo) == "function" then
    local info = ns.Call(C_Map.GetMapInfo, d[3])
    local name = type(info) == "table" and ns.Str(info.name)
    if name then return name end
  end
  return d[4]
end

-- min, max, source ("Questdon" or "table")
function ns.DungeonRange(inst)
  local api = rawget(_G, "QuestdonAPI")
  if type(api) == "table" and type(api.DungeonLevelRange) == "function" then
    local ok, lo, hi = pcall(api.DungeonLevelRange, inst)
    lo, hi = ok and ns.Num(lo), ok and ns.Num(hi)
    if lo and lo > 0 then return lo, (hi and hi >= lo) and hi or lo, "Questdon" end
  end
  local d = DUNGEONS[inst]
  if d then return d[1], d[2], "table" end
end

-- "13-20" (a single level when both ends are the same).
function ns.LevelRangeText(lo, hi)
  if not lo then return "" end
  if not hi or hi == lo then return ("%d"):format(lo) end
  return L["%d-%d"]:format(lo, hi)
end

-- Dungeons whose range holds your level, the ones that start closest to it
-- first: { { inst, name, min, max }, ... }
function ns.DungeonsForLevel(level)
  level = level or ns.Num(ns.Value(UnitLevel, "player"))
  local list = {}
  if not level then return list end
  local source = "table"
  for inst in pairs(DUNGEONS) do
    local lo, hi, src = ns.DungeonRange(inst)
    if src == "Questdon" then source = "Questdon" end
    if lo and level >= lo and level <= (hi or lo) then
      list[#list + 1] = { inst = inst, name = DungeonName(inst), min = lo, max = hi }
    end
  end
  stats.source = source
  table.sort(list, function(a, b)
    if a.min ~= b.min then return a.min > b.min end
    return a.name < b.name
  end)
  return list
end

-- The lowest dungeon level of all (for "no dungeon fits yet").
function ns.FirstDungeonLevel()
  local first
  for inst in pairs(DUNGEONS) do
    local lo = ns.DungeonRange(inst)
    if lo and (not first or lo < first) then first = lo end
  end
  return first
end
