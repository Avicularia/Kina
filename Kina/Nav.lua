-- Kina: navigation and NPC facts.
-- NPC levels, ranks, spawn points and item vendors come from the QuestieDB data
-- that ForeverVendors loads (global ForeverVendorsData), read only. Waypoints use
-- TomTom when installed, otherwise the game's own map pin.
local _, C = ...

-- QuestieDB keys (npc): 1 name, 4 minLevel, 5 maxLevel, 6 rank, 7 spawns,
-- 13 friendly faction, 14 sub name, 15 npc flags. (item): 14 vendors.
local RANKS = { [0] = "Normal", [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }

local function qdb()
  local D = rawget(_G, "ForeverVendorsData")
  if type(D) == "table" and type(D.GetScalar) == "function" and type(D.GetTable) == "function" then return D end
end
function C.HasNPCDatabase() return qdb() ~= nil end

local function areaToMap(area)
  local t = rawget(_G, "ForeverVendors_AreaToMap")
  return type(t) == "table" and t[area] or nil
end

function C.MapName(map)
  local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name, info and info.mapType
end

-- { nm, minLvl, maxLvl, rank, rankName, sub, faction, spawns = { {map, x, y}, ... } } or nil
local npcCache = {}
function C.NPCFacts(id)
  if npcCache[id] ~= nil then return npcCache[id] or nil end
  local D = qdb()
  if not D then return nil end
  local ok, facts = pcall(function()
    local name = D.GetScalar("Npc", id, 1)
    if not name then return false end
    local f = { nm = name, minLvl = D.GetScalar("Npc", id, 4), maxLvl = D.GetScalar("Npc", id, 5),
      rank = D.GetScalar("Npc", id, 6) or 0, sub = D.GetScalar("Npc", id, 14), faction = D.GetScalar("Npc", id, 13),
      spawns = {} }
    f.rankName = RANKS[f.rank] or "Normal"
    local sp = D.GetTable("Npc", id, 7)
    for area, pts in pairs(sp or {}) do
      local map = areaToMap(area)
      if map and type(pts) == "table" then
        for _, p in ipairs(pts) do
          if type(p[1]) == "number" and type(p[2]) == "number" and p[1] >= 0 then
            f.spawns[#f.spawns + 1] = { map, p[1] / 100, p[2] / 100 }
          end
        end
      end
    end
    return f
  end)
  npcCache[id] = (ok and facts) or false
  return npcCache[id] or nil
end

-- NPC IDs that sell an item (from the database), filtered to your faction.
function C.ItemVendors(itemID)
  local D = qdb()
  if not D then return {} end
  local ok, list = pcall(D.GetTable, "Item", itemID, 14)
  if not ok or type(list) ~= "table" then return {} end
  local mine = (UnitFactionGroup and UnitFactionGroup("player")) == "Horde" and "H" or "A"
  local out = {}
  for _, npc in ipairs(list) do
    local f = C.NPCFacts(npc)
    if f and (not f.faction or f.faction == "AH" or f.faction == mine) then out[#out + 1] = npc end
  end
  return out
end

------------------------------------------------------------------ position
function C.PlayerPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return map end
  local x, y = pos:GetXY()
  return map, x, y
end

-- Nearest of a list of {map, x, y}: same map as you first (by distance),
-- otherwise the first spawn in your continent order.
function C.Nearest(points)
  if not points or #points == 0 then return nil end
  local map, px, py = C.PlayerPos()
  local best, bestD
  for _, p in ipairs(points) do
    if p[1] == map and px then
      local d = (p[2] - px) ^ 2 + (p[3] - py) ^ 2
      if not bestD or d < bestD then best, bestD = p, d end
    end
  end
  return best or points[1], best ~= nil
end

-- Nearest vendor for an item: { npc, name, map, x, y, zone, sameZone } or nil.
function C.NearestVendor(itemID)
  local candidates = {}
  for _, npc in ipairs(C.ItemVendors(itemID)) do
    local f = C.NPCFacts(npc)
    for _, s in ipairs(f.spawns) do candidates[#candidates + 1] = { s[1], s[2], s[3], npc = npc } end
  end
  -- merchants you visited yourself (position recorded at the visit)
  local o = C.db.offers and C.db.offers[itemID]
  if o and o.map and o.x then candidates[#candidates + 1] = { o.map, o.x, o.y, name = o.who } end
  local p, same = C.Nearest(candidates)
  if not p then return nil end
  local f = p.npc and C.NPCFacts(p.npc)
  return { npc = p.npc, name = (f and f.nm) or p.name or "Vendor", map = p[1], x = p[2], y = p[3],
    zone = C.MapName(p[1]), sameZone = same }
end

------------------------------------------------------------------ waypoints
function C.Waypoint(map, x, y, title)
  if not (map and x and y) then C.Print("no location known."); return false end
  local tt = rawget(_G, "TomTom")
  if type(tt) == "table" and type(tt.AddWaypoint) == "function" then
    tt:AddWaypoint(map, x, y, { title = title or "Kina", source = "Kina", persistent = false, crazy = true })
  elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  else
    C.Print("no waypoint system available."); return false
  end
  C.Print(string.format("waypoint: %s, %s %.1f, %.1f", title or "?", C.MapName(map) or "?", x * 100, y * 100))
  return true
end

function C.WaypointToVendor(itemID)
  local v = C.NearestVendor(itemID)
  if not v then C.Print("no vendor known for that item."); return false end
  local r = C.Item(itemID)
  return C.Waypoint(v.map, v.x, v.y, v.name .. " (" .. ((r and r.name) or "item") .. ")")
end

------------------------------------------------------------------ difficulty
local CONTESTED = {
  ["Ashenvale"] = true, ["Stonetalon Mountains"] = true, ["Thousand Needles"] = true, ["Hillsbrad Foothills"] = true,
  ["Wetlands"] = true, ["Arathi Highlands"] = true, ["Badlands"] = true, ["Desolace"] = true, ["Dustwallow Marsh"] = true,
  ["Feralas"] = true, ["Stranglethorn Vale"] = true, ["Swamp of Sorrows"] = true, ["Tanaris"] = true,
  ["Searing Gorge"] = true, ["Burning Steppes"] = true, ["Azshara"] = true, ["Felwood"] = true, ["Un'Goro Crater"] = true,
  ["Winterspring"] = true, ["Blasted Lands"] = true, ["Eastern Plaguelands"] = true, ["Western Plaguelands"] = true,
  ["Silithus"] = true, ["Alterac Mountains"] = true, ["The Hinterlands"] = true, ["Deadwind Pass"] = true,
}
function C.IsPvPRuleset()
  local realm = (GetRealmName and GetRealmName()) or ""
  return realm:find("PvP") ~= nil
end

-- How hard is this mob for you? Returns label, colour hex, and notes.
function C.Difficulty(level, rankName, creatureType, zone)
  local me = (UnitLevel and UnitLevel("player")) or 1
  local class = UnitClass and select(2, UnitClass("player"))
  local notes = {}
  local label, color
  if not level then label, color = "Unknown level", "ffffff"
  else
    local d = level - me
    if d <= -6 then label, color = "Trivial (grey: little loot value, no XP)", "9d9d9d"
    elseif d <= -3 then label, color = "Easy", "1eff00"
    elseif d <= 2 then label, color = "Even", "ffff00"
    elseif d <= 4 then label, color = "Hard", "ff8000"
    else label, color = "Very hard", "ff2020" end
  end
  if rankName == "Elite" or rankName == "Rare Elite" or rankName == "Boss" then
    notes[#notes + 1] = (rankName == "Boss") and "Boss: dungeon lockout, group expected" or "Elite: about 3x health and damage; group or careful pulls"
  end
  if rankName == "Rare" or rankName == "Rare Elite" then notes[#notes + 1] = "Rare spawn: long respawn, not a repeatable farm" end
  if class == "ROGUE" and (creatureType == "Humanoid" or creatureType == "Undead") then
    notes[#notes + 1] = "Rogue: Pick Pocket before each kill for extra coin and junkboxes"
  end
  if creatureType == "Beast" and C.char.prof and C.char.prof["Skinning"] then notes[#notes + 1] = "Skinnable: you have Skinning" end
  if zone and CONTESTED[zone] then
    notes[#notes + 1] = C.IsPvPRuleset() and "Contested zone on a PvP ruleset: expect enemy players" or "Contested zone (PvE ruleset: low risk)"
  end
  return label, color, notes
end
