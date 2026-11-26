local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (26.11.2026, Daniel: "Die stateweight sollten auch in den optionen einstellbar sein ähnlich wie bei pawn") Your own
-- stat weights, one slider per stat on the options page "Stat weights", for the spec you play (class and talent tree,
-- like Pawn's scales per spec). The weights live in DonData (Engine/Gear.lua, DonDataAPI 5): the sliders start at the
-- spec's numbers from the Forever guides (hit and crit: their worth for you right now), what you change is kept here
-- per class and tree (db.statWeights["<class>:<tree>"]) and handed to DonData after each login and spec change. A slider
-- moved back to the guides' value counts as not changed. Without DonData 5 the page explains that it needs DonData.
-- The sliders show the current spec in db.sw_<stat>; their defaults (ns.defaults.sw_<stat>) follow the spec and your gear.
---------------------------------------------------------------------------
local function Fmt(v) return ("%.2f"):format(tonumber(v) or 0) end

-- key, max, step (min 0); name and tip are option texts (translated in Locales)
ns.STAT_WEIGHT_ITEMS = {
  { header = "Primary stats" },
  { key = "str", max = 5, step = 0.05, name = "Strength", tip = "Points per point of Strength." },
  { key = "agi", max = 5, step = 0.05, name = "Agility", tip = "Points per point of Agility, with the crit it gives you." },
  { key = "sta", max = 5, step = 0.05, name = "Stamina", tip = "Points per point of Stamina. Armor counts as the Stamina it is worth to you." },
  { key = "int", max = 5, step = 0.05, name = "Intellect", tip = "Points per point of Intellect." },
  { key = "spi", max = 5, step = 0.05, name = "Spirit", tip = "Points per point of Spirit." },
  { header = "Attack" },
  { key = "ap", max = 3, step = 0.05, name = "Attack power", tip = "Points per point of attack power." },
  { key = "rap", max = 3, step = 0.05, name = "Ranged attack power", tip = "Points per point of ranged attack power." },
  { key = "dps", max = 60, step = 0.5, name = "Weapon DPS", tip = "Points per 1 damage per second of a weapon you fight with." },
  { key = "hit", max = 120, step = 0.5, name = "Hit (per 1%)", tip = "Points per 1% hit, your hit now included as the character frame shows it. From level 50 up to the cap of 8%. Below level 50 in full up to 6% (mobs up to 2 levels above you), then a third up to 8%. Above it nothing." },
  { key = "crit", max = 120, step = 0.5, name = "Crit (per 1%)", tip = "Points per 1% crit. The start value is what 1% crit adds to your damage now." },
  { key = "wskill", max = 30, step = 0.25, name = "Weapon skill", tip = "Points per point of weapon skill, while you are under the hit cap." },
  { header = "Spells" },
  { key = "shit", max = 120, step = 0.5, name = "Spell hit (per 1%)", tip = "Points per 1% spell hit, your spell hit now included, also talents for one school such as Shadow Focus. From level 50 up to the cap of 17%. Below level 50 in full up to 6%, then a third up to 17%: bosses need it later. Above it nothing." },
  { key = "scrit", max = 120, step = 0.5, name = "Spell crit (per 1%)", tip = "Points per 1% spell crit. The start value is what 1% adds to your damage or healing now." },
  { key = "sd", max = 10, step = 0.05, name = "Spell power", tip = "Points per point of spell damage of all schools." },
  { key = "sd_holy", max = 10, step = 0.05, name = "Holy spell power", tip = "Points per point of holy spell damage." },
  { key = "sd_fire", max = 10, step = 0.05, name = "Fire spell power", tip = "Points per point of fire spell damage." },
  { key = "sd_nature", max = 10, step = 0.05, name = "Nature spell power", tip = "Points per point of nature spell damage." },
  { key = "sd_frost", max = 10, step = 0.05, name = "Frost spell power", tip = "Points per point of frost spell damage." },
  { key = "sd_shadow", max = 10, step = 0.05, name = "Shadow spell power", tip = "Points per point of shadow spell damage." },
  { key = "sd_arcane", max = 10, step = 0.05, name = "Arcane spell power", tip = "Points per point of arcane spell damage." },
  { key = "pen", max = 15, step = 0.05, name = "Spell penetration", tip = "Points per point of spell penetration." },
  { header = "Healing and regeneration" },
  { key = "heal", max = 10, step = 0.05, name = "Healing", tip = "Points per point of healing power." },
  { key = "mp5", max = 10, step = 0.05, name = "Mana per 5 sec.", tip = "Points per point of mana every 5 seconds." },
  { key = "hp5", max = 10, step = 0.05, name = "Health per 5 sec.", tip = "Points per point of health every 5 seconds." },
  { header = "Defense" },
  { key = "def", max = 5, step = 0.05, name = "Defense", tip = "Points per point of defense skill." },
  { key = "dodge", max = 60, step = 0.5, name = "Dodge (per 1%)", tip = "Points per 1% dodge." },
  { key = "parry", max = 60, step = 0.5, name = "Parry (per 1%)", tip = "Points per 1% parry." },
  { key = "block", max = 30, step = 0.5, name = "Block (per 1%)", tip = "Points per 1% block chance." },
  { key = "bv", max = 3, step = 0.05, name = "Block value", tip = "Points per point of block value." },
}

local function API()
  local api = rawget(_G, "DonDataAPI")
  if type(api) == "table" and (tonumber(api.version) or 0) >= 5 and type(api.GearShownWeights) == "function"
    and type(api.SetGearOverrides) == "function" then return api end
  return nil
end
ns.StatWeightsAPI = API

local current -- "<class>:<tree>" shown in the sliders
local shownClass, shownTree

-- the guides' values of the spec into the sliders' defaults; returns them
local function Defaults(api)
  local ok, w, class, tree = pcall(api.GearShownWeights, false)
  if not ok or type(w) ~= "table" then return nil end
  ns.defaults = ns.defaults or {}
  for _, it in ipairs(ns.STAT_WEIGHT_ITEMS) do
    if it.key then ns.defaults["sw_" .. it.key] = tonumber(w[it.key]) or 0 end
  end
  return w, class, tree
end

local function Store()
  ns.db.statWeights = type(ns.db.statWeights) == "table" and ns.db.statWeights or {}
  return ns.db.statWeights
end

-- your numbers of the current spec to DonData
local function Push(api)
  if not (current and shownClass) then return end
  local own = Store()[current]
  pcall(api.SetGearOverrides, shownClass, shownTree, type(own) == "table" and own or nil)
end

-- Follow the spec you play: its stored numbers into the sliders, its guides' values as their defaults, both to DonData.
function ns.SyncStatWeights()
  local api = API()
  if not (api and ns.db) then return false end
  local _, class, tree = Defaults(api)
  if not class then return false end
  local key = class .. ":" .. (tree or 0)
  if key ~= current then
    current, shownClass, shownTree = key, class, tree or 0
    local own = Store()[key]
    for _, it in ipairs(ns.STAT_WEIGHT_ITEMS) do
      if it.key then ns.db["sw_" .. it.key] = type(own) == "table" and tonumber(own[it.key]) or nil end
    end
    Push(api)
    if ns.ClearItemCache then ns.ClearItemCache() end
    if ns.Dirty then ns.Dirty() end
  end
  return true
end

-- A slider moved: what differs from the guides' value is kept for this spec and counts at once.
function ns.StatWeightChanged()
  local api = API()
  if not (api and ns.SyncStatWeights()) then return end
  local own = {}
  for _, it in ipairs(ns.STAT_WEIGHT_ITEMS) do
    if it.key then
      local v, d = tonumber(ns.db["sw_" .. it.key]), tonumber(ns.defaults["sw_" .. it.key]) or 0
      if v and math.abs(v - d) >= it.step / 2 then own[it.key] = v else ns.db["sw_" .. it.key] = nil end
    end
  end
  Store()[current] = next(own) and own or nil
  Push(api)
  if ns.BumpVersion then ns.BumpVersion() end
  if ns.ClearItemCache then ns.ClearItemCache() end
  if ns.Dirty then ns.Dirty() end
end

-- All sliders of this spec back to the guides' values.
function ns.ResetStatWeights()
  if not ns.SyncStatWeights() then return end
  Store()[current] = nil
  for _, it in ipairs(ns.STAT_WEIGHT_ITEMS) do if it.key then ns.db["sw_" .. it.key] = nil end end
  local api = API()
  if api then Push(api) end
  if ns.BumpVersion then ns.BumpVersion() end
  if ns.ClearItemCache then ns.ClearItemCache() end
  if ns.Dirty then ns.Dirty() end
end

-- "Fury warrior (your numbers)" style line for the page and the status
local TREE_NAMES = {
  [1] = { "Arms", "Fury", "Protection" }, [2] = { "Holy", "Protection", "Retribution" },
  [3] = { "Beast Mastery", "Marksmanship", "Survival" }, [4] = { "Assassination", "Combat", "Subtlety" },
  [5] = { "Discipline", "Holy", "Shadow" }, [7] = { "Elemental", "Enhancement", "Restoration" },
  [8] = { "Arcane", "Fire", "Frost" }, [9] = { "Affliction", "Demonology", "Destruction" },
  [11] = { "Balance", "Feral", "Restoration" },
}
function ns.StatWeightsSpecText()
  if not (API() and ns.SyncStatWeights()) then return nil end
  local fn = rawget(_G, "GetTalentTabInfo")
  local name
  if shownTree and shownTree > 0 and type(fn) == "function" then
    local ok, n = pcall(fn, shownTree)
    if ok and type(n) == "string" and n ~= "" then name = n end
  end
  name = name or (shownTree and shownTree > 0 and TREE_NAMES[shownClass] and L[TREE_NAMES[shownClass][shownTree]])
    or L["No talents yet"]
  local own = Store()[current]
  return own and L["Stat weights: %s (your numbers)"]:format(name) or L["Stat weights: %s (from the guides)"]:format(name)
end

-- the options page (Options.lua puts it after "Upgrade arrow")
function ns.StatWeightPage()
  local blocked = function()
    if API() then return nil end
    return { reason = L["Needs DonData 1.7 or newer (comes with Questdon)."] }
  end
  local items = {
    { kind = "button", name = "Back to the guides' values", button = "Reset", tip = "Puts every weight of the spec you play back to the values from the WoW Forever guides (Icy Veins, Warcraft Tavern).",
      onClick = function() ns.ResetStatWeights() end },
  }
  for _, it in ipairs(ns.STAT_WEIGHT_ITEMS) do
    if it.header then
      items[#items + 1] = { header = it.header }
    else
      items[#items + 1] = { key = "sw_" .. it.key, kind = "slider", name = it.name, tip = it.tip, min = 0, max = it.max,
        step = it.step, format = Fmt, blockedBy = blocked, onChange = function() ns.StatWeightChanged() end }
    end
  end
  return { title = "Stat weights", tip = "Your own stat weights for the spec you play, like Pawn's scales. They start at the values from the WoW Forever guides; the arrow, the percent in the tooltip and Questdon's reward advice use them.", items = items }
end

for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP",
    "PLAYER_EQUIPMENT_CHANGED" }) do
  ns.On(e, function()
    -- the defaults of hit and crit move with your gear and level; the spec with your talents
    current = (e == "PLAYER_EQUIPMENT_CHANGED" or e == "PLAYER_LEVEL_UP") and current or nil
    if e == "PLAYER_EQUIPMENT_CHANGED" or e == "PLAYER_LEVEL_UP" then
      local api = API()
      if api then Defaults(api) end
    else
      ns.SyncStatWeights()
    end
  end)
end
