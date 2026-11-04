-- Kina: farm ranker.
-- Ranks every mob you or the ForeverGuide community have looted by estimated gold
-- per hour, splitting NPC-paid money (coin, pickpocket) from item value.
-- ForeverGuide is read only; Kina never writes to it.
local _, C = ...

local function fgData()
  local db = rawget(_G, "ForeverGuideDB")
  if type(db) ~= "table" or type(db.comm) ~= "table" then return nil end
  return db
end

-- Pool ForeverGuide community reports per npc: kills and notable item counts.
local fgCache, fgStamp, fgBuilt
local function fgPool()
  do return {} end -- 0.11.0: ForeverGuide's community data is no longer used (drop data comes from the Wowhead Forever snapshot)
  local db = fgData()
  if not db then return {} end
  -- ForeverGuide keeps adding community kills to the same table: rebuild every 5 min
  if fgCache and fgStamp == db.comm and C.Now() - (fgBuilt or 0) < 300 then return fgCache end
  fgBuilt = C.Now()
  local pool = {}
  -- your own characters' reports are already in your own loot records: skip them
  local mine = {}
  for key in pairs(C.db.chars or {}) do mine[(key:match("^([^%-]+)") or key):lower()] = true end
  for npc, reporters in pairs(db.comm) do
    if type(reporters) == "table" then
      local p = { kills = 0, items = {} }
      for who, rec in pairs(reporters) do
        if type(rec) == "table" and type(rec.k) == "number" and not (type(who) == "string" and mine[(who:match("^([^%-]+)") or who):lower()]) then
          p.kills = p.kills + rec.k
          if type(rec.i) == "table" then
            for id, n in pairs(rec.i) do p.items[id] = (p.items[id] or 0) + n end
          end
        end
      end
      if p.kills > 0 then pool[npc] = p end
    end
  end
  for npc, r in pairs(db.npcloot or {}) do if pool[npc] and type(r) == "table" then pool[npc].nm = r.nm end end
  -- drop sightings carry the mob name, map and coordinates
  for _, byNpc in pairs(db.drops or {}) do
    if type(byNpc) == "table" then
      for key, d in pairs(byNpc) do
        local npc = type(key) == "string" and tonumber(key:match("^c(%d+)$"))
        local p = npc and pool[npc]
        if p and type(d) == "table" then
          p.nm = p.nm or d.nm
          if d.m and not p.map then p.map, p.x, p.y = d.m, d.x, d.y end
        end
      end
    end
  end
  fgCache, fgStamp = pool, db.comm
  return pool
end
C.ForeverGuidePool = fgPool

-- The community pool Kina ranks with: for each mob, the biggest sample among your
-- ForeverGuide data and the data your Kina group shared (never added together: they
-- may contain the same reports).
local merged, mergedKey
local function poolFor()
  do return {} end -- 0.11.0: no community pools (see the drop snapshot)
  local own = fgPool()
  local others = C.Share and C.Share.CommPools and C.Share.CommPools() or {}
  local key = tostring(own) .. "|" .. #others
  for _, o in ipairs(others) do key = key .. "|" .. tostring(o.npcs) end
  if merged and mergedKey == key then return merged end
  local m = {}
  for npc, p in pairs(own) do m[npc] = p end
  for _, o in ipairs(others) do
    for npc, p in pairs(o.npcs) do
      local cur = m[npc]
      if not cur or (p.kills or 0) > (cur.kills or 0) then
        m[npc] = { kills = p.kills, items = p.items, nm = cur and cur.nm, map = cur and cur.map, x = cur and cur.x, y = cur and cur.y, from = o.name }
      end
    end
  end
  merged, mergedKey = m, key
  return m
end
C.FarmPool = poolFor

------------------------------------------------------------------ npc names
-- The client can describe any NPC by ID through a unit hyperlink tooltip: line 1
-- is the name, line 2 holds "Level NN <type>". Results are cached in saved data.
-- Read-only tooltip data; no protected calls, no hooks.
local scanTip
local function tipLines(id)
  local link = "unit:Creature-0-0-0-0-" .. id .. "-0000000000"
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local data = C_TooltipInfo.GetHyperlink(link)
    if data and data.lines and data.lines[1] then
      return data.lines[1].leftText, data.lines[2] and data.lines[2].leftText, data.lines[3] and data.lines[3].leftText
    end
    return nil
  end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "KinaScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  scanTip:SetHyperlink(link)
  local l1, l2, l3 = _G.KinaScanTipTextLeft1, _G.KinaScanTipTextLeft2, _G.KinaScanTipTextLeft3
  return l1 and l1:GetText(), l2 and l2:GetText(), l3 and l3:GetText()
end

local lookups = 0 -- new tooltip lookups this refresh (capped so a refresh stays fast)
function C.ResetNPCLookups() lookups = 0 end
function C.NPCInfo(id)
  C.db.npcs = C.db.npcs or {}
  local known = C.db.npcs[id]
  if known then return known end
  -- best source: the NPC database ForeverVendors loads (level range, rank, spawns)
  local q = C.NPCFacts and C.NPCFacts(id)
  if q then
    known = { nm = q.nm, lvl = q.minLvl, maxLvl = q.maxLvl, elite = (q.rank == 1 or q.rank == 2 or q.rank == 3),
      rare = (q.rank == 2 or q.rank == 4) or nil, rankName = q.rankName, fromDB = true }
    local first = q.spawns[1]
    if first then known.zone = C.MapName(first[1]) end
    return known
  end
  known = C.Data.npcs and C.Data.npcs[id]
  if known then return known end
  -- ask at most 5 times per session for a name the client never returns, so dead
  -- IDs cannot use up the per-refresh budget and starve the rest
  C.npcTries = C.npcTries or {}
  if lookups >= 150 or (C.npcTries[id] or 0) >= 5 then return nil end
  lookups = lookups + 1
  C.npcTries[id] = (C.npcTries[id] or 0) + 1
  local ok, name, l2, l3 = pcall(tipLines, id)
  if not ok or not name or name == "" then return nil end
  local info = { nm = name, elite = false }
  for _, line in ipairs({ l2 or "", l3 or "" }) do
    if line:find(LEVEL or "Level") then
      local lvl = line:match("(%d+)")
      info.lvl = tonumber(lvl)
      info.type = line:gsub("%b()", ""):match("(%a+)%s*$")
      -- "(Elite)", "(Rare Elite)", "(Boss)" or "Level ??" all mean not open-world farmable
      if line:find(ELITE or "Elite") or line:find("Boss") or line:find("%?%?") then info.elite = true end
      if line:find("Rare") then info.rare = true end
      break
    end
  end
  C.db.npcs[id] = info
  return info
end

-- What one looted item is worth for farm math. A thin AH market (under 3 listings)
-- is someone's asking price, not a market: use the safer of what a vendor pays, the
-- disenchant value, or the typical price from your scan history (3+ days).
local function historyMedian(id)
  local h = C.market.history and C.market.history[id]
  if not h then return nil end
  local vals = {}
  for _, d in pairs(h) do if type(d) == "table" and (d[2] or d[1]) then vals[#vals + 1] = d[2] or d[1] end end
  if #vals < 3 then return nil end
  table.sort(vals)
  return vals[math.floor((#vals + 1) / 2)]
end
-- Bind on Pickup (and quest) items: recorded as obtained, never counted as money in
-- a farm or a split (vendoring one later shows up as real gold anyway).
function C.IsBound(id)
  local r = C.Item and C.Item(id)
  return r and (r.bind == 1 or r.bind == 4) and true or false
end
function C.FarmValue(id, suffix)
  if C.IsBound(id) then return 0, "BOUND" end
  local route, v, det = C.BestRoute(id, 1)
  v = v or 0
  -- a known roll ("of the Eagle", read from the loot line): that roll's own AH price
  -- when 2+ of that roll are listed; never below disenchanting or the vendor
  if suffix then
    local mi = C.MarketItem(id)
    local r = mi and mi.sxn and mi.sxn[suffix]
    if r and (r[2] or 0) >= 2 then
      local ah = r[1] * (1 - C.settings.ahCut)
      local best = math.max(ah, det and det.vendor or 0, det and det.de and det.de.ev or 0)
      return best, best == ah and "affix" or "DISENCHANT"
    end
  end
  -- green/blue gear that rolls random affixes ("of the Monkey"): you can't know which
  -- roll will drop, and each roll is its own thin market. Count the AH only when 3+
  -- listings exist across all rolls, and then only at the CHEAPEST roll's price;
  -- otherwise disenchanting or the vendor decides.
  local mi = C.MarketItem(id)
  local ir = C.Item(id)
  if mi and mi.sl and #mi.sl > 0 and ir and C.IsGear(ir) and (ir.q or 0) >= 2 then
    local rows = mi.n or 0
    for _, e in ipairs(mi.sl) do rows = rows + (e[3] or 1) end
    -- 1-2 listings: an asking price, not a sale; count it at 75%
    local ah = mi.any and ((rows >= 3 and mi.any * (1 - C.settings.ahCut)) or (rows >= 1 and mi.any * (1 - C.settings.ahCut) * 0.75)) or 0
    local vend, de = det and det.vendor or 0, det and det.de and det.de.ev or 0
    local best = math.max(ah, vend, de)
    return best, (best == ah and ah > 0) and "affix" or ((best == de and de > 0) and "DISENCHANT" or "VENDOR")
  end
  if det and det.ah and v == det.ah then
    local mi = C.MarketItem(id)
    if mi and (mi.n or 0) < 3 then
      -- (gear is always thinly listed: its 1-2 listings already count at 75% in the AH price)
      local ir2 = C.Item(id)
      if ir2 and C.IsGear(ir2) then return v, route end
      local safe = math.max(det.vendor or 0, det.de and det.de.ev or 0, (historyMedian(id) or 0) * (1 - C.settings.ahCut))
      return safe, "thin"
    end
  end
  return v, route
end
local function unitValue(id, n)
  return (C.FarmValue(id))
end

local function valuePerKill(items, kills)
  if not items or kills <= 0 then return 0, nil end
  local total, bestID, bestV = 0, nil, 0
  for id, n in pairs(items) do
    local v = unitValue(id, n) * n
    total = total + v
    if v > bestV then bestV, bestID = v, id end
  end
  return total / kills, bestID
end

-- Gathering on a farm (herbs, ore... from nodes), measured by the farm widget: value
-- and nodes per kill, from timed farms where this mob was at least half the kills.
local function measuredGather(npc)
  local val, kills, nodes, n = 0, 0, 0, 0
  for _, s in ipairs(C.db.sessions or {}) do
    local k = s.byNpc and s.byNpc[npc]
    if s.gather and k and (s.kills or 0) > 0 and k / s.kills >= 0.5 then
      local share = k / s.kills
      val = val + C.SessionItemValue(s, s.gather) * share
      nodes = nodes + (s.nodes or 0) * share
      kills = kills + k; n = n + 1
    end
  end
  if kills >= 20 then return val / kills, nodes / kills * 60, n end
end

-- What one drop is worth when a farm brings in `perHour` of them: the AH only buys
-- about Velocity(id) an hour (measured from scan to scan, or a cautious estimate);
-- the rest goes to the vendor or disenchanting. Returns value, route, share sold on AH.
local function cappedValue(id, perHour)
  local v, route = C.FarmValue(id)
  v = v or 0
  if not (route == "AUCTION" or route == "SELL" or route == "affix") or not perHour or perHour <= 0 then return v, route, 1 end
  local vel = C.Econ and C.Econ.Velocity and C.Econ.Velocity(id) or perHour
  local f = math.min(1, vel / perHour)
  if f >= 1 then return v, route, 1 end
  local _, _, det = C.BestRoute(id, 1)
  local fallback = math.max(det and det.vendor or 0, det and det.de and det.de.ev or 0)
  return f * v + (1 - f) * math.min(fallback, v), route, f
end
C.CappedValue = cappedValue

-- Measured kills per hour for an npc: sessions where it was most of the kills.
local function measuredKPH(npc)
  local kills, secs = 0, 0
  for _, s in ipairs(C.db.sessions) do
    local k = s.byNpc and s.byNpc[npc]
    if k and s.kills > 0 and k / s.kills >= 0.5 and s.result then
      kills = kills + k; secs = secs + s.result.secs * (k / s.kills)
    end
  end
  if kills >= 20 and secs > 0 then return kills * 3600 / secs, true end
  return nil, false
end

-- Your loot record merged with what other Kina users shared (Share.lua).
local function lootRecord(npc)
  if C.LootRecord then return C.LootRecord(npc) end
  return C.db.loot[npc]
end
local function lootNPCs()
  if C.LootNPCs then return C.LootNPCs() end
  return C.db.loot
end

------------------------------------------------------------------ world drops
-- World drops: every green-or-better item, recipe and scroll, unless it clearly
-- belongs to one mob (5+ sightings, 80%+ of them from that mob). Plain items count as
-- world drops when seen from 5+ different mobs. A world drop's value per kill comes
-- from ALL kills of normal mobs within 2 levels, so one lucky drop can't skew a mob.
local WORLD_SOURCES, BAND = 5, 2
local function rareKind(id)
  local r = C.Item(id)
  if not r then return false end
  return (r.q or 0) >= 2 or r.cls == 9 or (r.name and r.name:find("^Scroll")) and true or false
end
local world -- { pool, t, isWorld = {id=true}, npcs = { {lvl, kills, items} }, band = {} }
local function npcLevelElite(npc, own)
  local lvl, elite = own and own.lvl, own and own.elite
  local n = C.db.npcs and C.db.npcs[npc]
  if n then lvl = lvl or n.lvl; if elite == nil then elite = n.elite end end
  local d = C.Data.npcs and C.Data.npcs[npc]
  if d then lvl = lvl or d.lvl; if elite == nil then elite = d.elite end end
  return lvl, elite
end
local function worldData(pool)
  if world and world.pool == pool and C.Now() - world.t < 300 then return world end
  local sources = {}
  local function note(id, npc, c)
    local s = sources[id]
    if not s then s = { n = 0, total = 0, by = {} }; sources[id] = s end
    if not s.by[npc] then s.n = s.n + 1 end
    s.by[npc] = (s.by[npc] or 0) + c; s.total = s.total + c
  end
  local own = lootNPCs()
  for npc, p in pairs(pool) do for id, c in pairs(p.items) do note(id, npc, c) end end
  for npc in pairs(own) do local r = lootRecord(npc); for id, c in pairs(r and r.items or {}) do note(id, npc, c) end end
  local isWorld = {}
  for id, s in pairs(sources) do
    local top = 0
    for _, c in pairs(s.by) do if c > top then top = c end end
    local ownsIt = s.total >= 5 and top / s.total >= 0.8
    if rareKind(id) then isWorld[id] = not ownsIt
    elseif s.n >= WORLD_SOURCES then isWorld[id] = true end
  end
  -- every normal mob with a known level: kills and world-drop counts (yours + community)
  local npcs, seen = {}, {}
  local function add(npc)
    if seen[npc] then return end
    seen[npc] = true
    local r, p = own[npc] and lootRecord(npc), pool[npc]
    local lvl, elite = npcLevelElite(npc, r)
    if not lvl or elite then return end
    local kills = (r and math.max(r.kills or 0, r.looted or 0) or 0) + (p and p.kills or 0)
    if kills <= 0 then return end
    local items = {}
    for id, n in pairs(r and r.items or {}) do if isWorld[id] then items[id] = (items[id] or 0) + n end end
    for id, n in pairs(p and p.items or {}) do if isWorld[id] then items[id] = (items[id] or 0) + n end end
    npcs[#npcs + 1] = { lvl = lvl, kills = kills, items = items }
  end
  for npc in pairs(own) do add(npc) end
  for npc in pairs(pool) do add(npc) end
  world = { pool = pool, t = C.Now(), isWorld = isWorld, npcs = npcs, band = {} }
  return world
end
-- World-drop value per kill around a level: value, kills in the sample, item rates
local function bandValue(w, lvl)
  if not lvl then return 0, 0, {} end
  local b = w.band[lvl]
  if b then return b.v, b.kills, b.rates end
  local kills, counts = 0, {}
  for _, e in ipairs(w.npcs) do
    if math.abs(e.lvl - lvl) <= BAND then
      kills = kills + e.kills
      for id, n in pairs(e.items) do counts[id] = (counts[id] or 0) + n end
    end
  end
  local rates, v = {}, 0
  if kills > 0 then
    for id, n in pairs(counts) do rates[id] = n / kills; v = v + rates[id] * C.FarmValue(id) end
  end
  w.band[lvl] = { v = v, kills = kills, rates = rates }
  return v, kills, rates
end
C.FarmWorld = function() return world end
C.IsWorldDrop = function(id) return world and world.isWorld[id] or false end
C.WorldBand = function(lvl) local w = world or worldData(fgPool()); return bandValue(w, lvl) end


------------------------------------------------------------------ drop snapshot
-- Drop rates come from a snapshot of Wowhead Forever (DropData.lua), taken once per
-- major Kina release: tens of thousands of loots per mob, the same file for everyone
-- in your group, so everyone ranks farms alike. Each mob keeps its own drops (meat,
-- beaks, cloth, greys, its own blues); its green/blue/epic world drops use how often
-- IT drops them, with WHICH item from its level's pool across all mobs.
local snap
local function snapshot()
  if snap then return snap end
  snap = { mobs = {}, pools = {}, n = 0 }
  for line in (C.Data.dropMobsRaw or ""):gmatch("[^\n]+") do
    local head, items, name = line:match("^([^|]*)|([^|]*)|(.*)$")
    if head then
      local f = {}
      for v in head:gmatch("[^,]+") do f[#f + 1] = tonumber(v, 36) end
      if f[1] and f[4] and f[4] > 0 then
        local m = { id = f[1], lvl = f[2], type = f[3], loots = f[4], q = { [2] = f[5] or 0, [3] = f[6] or 0, [4] = f[7] or 0, [9] = f[8] or 0 },
          items = {}, nm = name, elite = f[9] == 1 or f[9] == 3, boss = f[10] == 1, loc = f[11] }
        for id, c in items:gmatch("(%w+)%.(%w+)") do m.items[tonumber(id, 36)] = tonumber(c, 36) end
        snap.mobs[m.id] = m; snap.n = snap.n + 1
      end
    end
  end
  snap.ids = {}
  for _, m in pairs(snap.mobs) do for id in pairs(m.items) do snap.ids[id] = true end end
  for line in (C.Data.dropPoolsRaw or ""):gmatch("[^\n]+") do
    local lv, q, items = line:match("^(%w+):(%w+)|(.*)$")
    if lv then
      lv, q = tonumber(lv, 36), tonumber(q, 36)
      local p = snap.pools[lv] or {}
      snap.pools[lv] = p
      local t = { total = 0, items = {}, top = 0 }
      for id, c in items:gmatch("(%w+)%.(%w+)") do c = tonumber(c, 36); id = tonumber(id, 36); snap.ids[id] = true; t.items[id] = c; t.total = t.total + c; if c > t.top then t.top = c end end
      p[q] = t
    end
  end
  -- ask the client about every item once, so prices can be worked out
  if C.LoadItems then
    local list = {}
    for id in pairs(snap.ids) do if not (C.db.items and C.db.items[id]) then list[#list + 1] = id end end
    if #list > 0 then C.LoadItems(list, function() if C.Refresh then C.Refresh() end end) end
  end
  return snap
end
C.DropSnapshot = snapshot
local TYPE = { [1] = "Beast", [2] = "Dragonkin", [3] = "Demon", [4] = "Elemental", [5] = "Giant", [6] = "Undead", [7] = "Humanoid", [8] = "Critter", [9] = "Mechanical" }

-- average value of one world drop of quality q at a level (cached per scan)
local poolVal, poolValScan = {}, nil
local function poolValue(lvl, q)
  if poolValScan ~= C.market.scanTime then poolVal, poolValScan = {}, C.market.scanTime end
  local key = lvl * 10 + q
  if poolVal[key] then return poolVal[key] end
  local p = (snapshot().pools[lvl] or {})[q]
  local v = 0
  if p and p.total > 0 then for id, c in pairs(p.items) do v = v + c / p.total * unitValue(id) end end
  poolVal[key] = v
  return v
end
-- a snapshot mob's world drops: value per kill, and (only when asked) each item's rate
local function snapWorld(m, wantRates, thr)
  local val, rates, common = 0, wantRates and {} or nil, 0
  for q, cnt in pairs(m.q) do
    if cnt > 0 then
      local qRate = cnt / m.loots
      val = val + qRate * poolValue(m.lvl, q)
      local p = (snapshot().pools[m.lvl] or {})[q]
      if p and p.total > 0 and (wantRates or (thr and qRate * p.top / p.total >= thr)) then
        for id, c in pairs(p.items) do
          local r = qRate * c / p.total
          if rates then rates[id] = (rates[id] or 0) + r end
          if thr and r >= thr then common = common + r * unitValue(id) end
        end
      end
    end
  end
  return val, rates, common
end
function C.SnapWorld(npc)
  local m = snapshot().mobs[npc]
  if not m then return 0, 0, {} end
  local v, rates = snapWorld(m, true)
  return v, m.loots, rates
end
C.WorldBand = function() return 0, 0, {} end

-- Zones (Wowhead Forever): faction territory and whether it is an instance
local zones
function C.ZoneInfo(area)
  if not zones then
    zones = {}
    for id, terr, inst in (C.Data.zonesRaw or ""):gmatch("(%d+):(%d+):(%d+)") do
      zones[tonumber(id)] = { terr = tonumber(terr), inst = tonumber(inst) }
    end
  end
  return area and zones[area]
end
-- your own records: killed inside a dungeon (flag from 0.16.0, or a dungeon map in its locations)
local function ownInDungeon(own)
  if not own then return nil end
  if own.inst then return true end
  for map in pairs(own.locs or {}) do
    local ok, info = pcall(function() return C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map) end)
    if ok and info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Dungeon then return true end
  end
  return nil
end
-- 0 Alliance, 1 Horde: the territory number of your faction
local function myTerritory()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return (f == "Alliance" and 0) or (f == "Horde" and 1) or nil
end

-- Returns a ranked list.
-- opts.lo / opts.hi: level band (mobs of unknown level are left out of a band).
-- opts.kind: "world" (normal mobs, ranked by gold/hour) or "dungeon" (elites and
-- bosses, ranked by value per kill: lockouts cap how often you can kill them).
function C.RankFarms(opts)
  opts = opts or {}
  -- who is farming: class, solo/duo, who skins, who disenchants (Duo.lua)
  local pf = opts.profile or (C.FarmProfile and C.FarmProfile()) or {}
  C.ResetNPCLookups()
  local pool = poolFor()
  local rows, seen = {}, {}
  local pending = 0
  local S = snapshot()
  local function build(npc)
    if seen[npc] then return end
    seen[npc] = true
    local own = lootRecord(npc)
    local sm = S.mobs[npc]
    if sm and sm.loots < 100 then sm = nil end -- too few loots on Wowhead to trust
    local fg = nil
    local ownKills = own and math.max(own.kills or 0, own.looted or 0) or 0
    local fgKills = sm and sm.loots or 0
    if not sm and ownKills < 20 then return end
    -- one or two spawn points: a named rare or a quest mob, not something you can farm
    local facts = C.NPCFacts and C.NPCFacts(npc)
    local unique = facts and facts.spawns and #facts.spawns > 0 and #facts.spawns <= 2 or false
    if unique and not opts.all and not C.settings.showUnique then return end
    local info
    if sm then
      -- name, level and type from the snapshot so every Kina agrees; zone from the NPC database
      info = { nm = sm.nm, lvl = sm.lvl, elite = sm.elite, type = TYPE[sm.type] }
      if sm.loc and sm.loc > 0 and C_Map and C_Map.GetAreaInfo then
        local ok, zn = pcall(C_Map.GetAreaInfo, sm.loc); if ok and zn and zn ~= "" then info.zone = zn end
      end
      local f = not info.zone and C.NPCFacts and C.NPCFacts(npc)
      if f and f.spawns and f.spawns[1] then info.zone = C.MapName(f.spawns[1][1]) end
    else
      info = (not (own and own.nm and own.lvl and own.elite ~= nil)) and C.NPCInfo(npc) or nil
    end
    if not info and not (own and own.nm) then pending = pending + 1 end
    local lvl = sm and sm.lvl or (own and own.lvl) or (info and info.lvl)
    local elite
    if sm then elite = sm.elite elseif own and own.elite ~= nil then elite = own.elite elseif info then elite = info.elite end
    local rare = not sm and ((own and own.rare) or (info and info.rare)) or nil
    if opts.lo and not opts.all and (not lvl or lvl < opts.lo or lvl > opts.hi) then return end
    if opts.all and opts.match and not opts.match((info and info.nm) or (own and own.nm) or "", npc) then return end
    -- elites count as open-world farms when you (or your duo) can kill them steadily
    local soloElite = elite == true and not rare and pf.eliteMax and lvl and lvl <= pf.eliteMax
    -- where it lives: dungeons are dungeons even when their mobs aren't elite, and
    -- the other faction's zones (and its dungeons) are hidden unless asked for
    local z = sm and C.ZoneInfo(sm.loc)
    local inDungeon = z and z.inst and z.inst > 0
    if ownInDungeon(own) then inDungeon = true end
    local mine = myTerritory()
    local enemy = z and mine and (z.terr == 0 or z.terr == 1) and z.terr ~= mine
    if not opts.all then
      if enemy and not C.settings.showEnemy then return end
      if inDungeon ~= nil and (z or inDungeon) then
        if opts.kind == "world" and (inDungeon or ((elite ~= false and not soloElite) or rare)) then return end
        if opts.kind == "dungeon" and not inDungeon and elite ~= true then return end
      else
        if opts.kind == "world" and ((elite ~= false and not soloElite) or rare) then return end
        if opts.kind == "dungeon" and elite ~= true then return end
      end
    end
    -- coin: own (plus party-shared) when 10+ kills, otherwise the level prior
    -- Weighted math: every number starts from a base estimate and moves toward what you
    -- (and your group) actually measured, in proportion to how many kills back it.
    -- PRIOR_KILLS = how many kills the base estimate is "worth".
    local PRIOR_KILLS = tonumber(C.settings.priorKills) or 50
    local coin, coinBasis = 0, "none"
    local prior = lvl and C.Data.CoinPrior(lvl, (own and own.type) or (info and info.type)) or nil
    if own and ownKills > 0 and prior then
      coin = (prior * 10 + own.coin) / (10 + ownKills) -- coin settles fast: 10 kills of weight
      coinBasis = ownKills >= 10 and (((own.sharedKills or 0) > 0) and "yours+party" or "yours") or "prior+yours"
    elseif own and ownKills > 0 then coin = own.coin / ownKills; coinBasis = "yours"
    elseif prior then coin = prior; coinBasis = "prior" end
    -- items: this mob's own drops from the pooled data (your kills + the community's,
    -- your own community reports excluded); world drops from every mob within 2 levels
    -- items: the snapshot's drops for this mob (identical for everyone), or, for mobs
    -- the snapshot doesn't cover, your own (and your group's) loot
    local thr = (tonumber(C.settings.rareRate) or 2.5) / 100
    local items, worldVal, worldKills, worldCommon = {}, 0, 0, 0
    local itemBasis
    if sm then
      for id, c in pairs(sm.items) do items[id] = c / sm.loots end
      worldVal, _, worldCommon = snapWorld(sm, false, thr)
      worldKills = sm.loots
      itemBasis = "base"
      -- blend in your own kills: the base counts as PRIOR_KILLS kills
      if own and ownKills > 0 and own.items then
        local w0 = PRIOR_KILLS
        local blended = {}
        for id, r in pairs(items) do blended[id] = r * w0 end
        for id, n in pairs(own.items) do blended[id] = (blended[id] or 0) + n end
        for id, v in pairs(blended) do blended[id] = v / (w0 + ownKills) end
        items = blended
        local share = ownKills / (w0 + ownKills)
        worldVal, worldCommon = worldVal * (1 - share), worldCommon * (1 - share) -- your kills already include world drops
        itemBasis = string.format("%d%% yours", math.floor(share * 100 + 0.5))
      end
    elseif own then
      for id, n in pairs(own.items) do items[id] = n / ownKills end
      itemBasis = "yours"
    end
    -- each drop at what the market can actually take at this farm's pace
    local kph0 = measuredKPH(npc) or (pf.kph and pf.kph(elite)) or C.settings.killsPerHour or 60
    local mobVal, best, bestV, caps = 0, nil, 0, nil
    local common = worldCommon
    for id, rate in pairs(items) do
      local u, _, f = cappedValue(id, rate * kph0)
      local v = u * rate
      mobVal = mobVal + v
      if v > bestV then bestV, best = v, id end
      if f < 1 then caps = caps or {}; caps[id] = f end
      -- the same without rare drops (anything under the Rare % box on the Farms tab)
      if rate >= thr then common = common + v end
    end
    local itemVal = mobVal + worldVal
    -- grey/vendor-trash share of the item value
    local junkItems = {}
    for id, rate in pairs(items) do local ir = C.Item(id); if ir and ir.q == 0 then junkItems[id] = rate end end
    local junkVal = valuePerKill(junkItems, 1)
    local skinVal = own and own.skins > 0 and ownKills > 0 and valuePerKill(own.skinItems, ownKills) or 0
    local ctype = (sm and info.type) or (own and own.type) or (info and info.type)
    local skinBasis = skinVal > 0 and "yours" or nil
    if skinVal == 0 and pf.skinner and ctype == "Beast" and not (C.NoSkin and C.NoSkin(npc)) and lvl and C.SkinEstimate then
      -- nobody has skinned it yet: Classic leather for its level at today's prices
      skinVal = C.SkinEstimate(lvl, pf.skinner); skinBasis = skinVal > 0 and "estimate" or nil
    elseif skinVal > 0 and not pf.skinner then skinVal = 0 end
    local ppVal = 0
    if own and own.pp > 0 and ownKills > 0 then ppVal = (own.ppCoin + (valuePerKill(own.ppItems, 1))) / ownKills end
    local kph, measured = measuredKPH(npc)
    kph = kph or (pf.kph and pf.kph(elite)) or C.settings.killsPerHour
    local gatherVal, nodes60, gatherFarms = measuredGather(npc)
    gatherVal = gatherVal or 0
    local perKillTotal = coin + itemVal + skinVal + ppVal + gatherVal
    local commonTotal = coin + common + skinVal + ppVal + gatherVal
    -- your share: the loot of every kill is split across the group
    local group = C.GroupSize and C.GroupSize() or 1
    local perKill = perKillTotal / group
    -- gold per hour: the estimate (per kill x kills per hour), moved toward your timed
    -- farms (farm widget) by how many hours you timed; one timed hour weighs as much as
    -- the estimate
    local rate = C.MeasuredRate and C.MeasuredRate(npc) or nil
    -- town trips: unstackable drops fill your bags; each trip costs pf.tripMin minutes.
    -- Green/blue gear an enchanter disenchants on the spot turns into stacking mats.
    local slots = 0
    for id, rate in pairs(items) do
      local ir = C.Item(id)
      if ir and C.IsGear(ir) then
        local deNow = pf.deSkill and ir.q and ir.q >= 2 and ir.q <= 3 and ir.il and C.DESkillNeeded(ir.il) <= pf.deSkill
        slots = slots + (deNow and 0.05 or 1) * rate
      else slots = slots + rate / 20 end
    end
    local tripsPerHour = (slots * kph) / math.max(10, pf.bagSlots or 70)
    local tripLoss = math.min(0.5, tripsPerHour * (pf.tripMin or 8) / 60)
    rows[#rows + 1] = {
      npc = npc, name = (sm and sm.nm) or (own and own.nm) or (info and info.nm) or (fg and fg.nm) or ("NPC " .. npc), level = lvl,
      zone = (own and own.zone) or (info and info.zone) or (fg and fg.map and C.MapName(fg.map)),
      x = fg and fg.x, y = fg and fg.y, type = ctype, loc = sm and sm.loc,
      ownKills = ownKills, fgKills = fgKills, snapLoots = sm and sm.loots or nil, snapQ = sm and sm.q or nil, sharedKills = own and own.sharedKills or 0,
      coin = coin, coinBasis = coinBasis, caps = caps, kph0 = kph0, unique = unique, gather = gatherVal, nodes60 = nodes60, gatherFarms = gatherFarms,
      items = itemVal, itemsJunk = junkVal, itemsGood = itemVal - junkVal, skins = skinVal, pickpocket = ppVal, perKill = perKill,
      perKillTotal = perKillTotal, group = group, perKillCommon = commonTotal / group, commonTotal = commonTotal, rareThreshold = thr, mobVal = mobVal, worldVal = worldVal, worldKills = worldKills, mobRates = items,
      kph = kph, kphMeasured = measured, rate = rate, itemBasis = itemBasis,
      -- the estimate leaves out rare drops (they make the average, not a normal hour)
      perHourEst = (commonTotal / group) * kph * (1 - tripLoss),
      perHour = (function()
        local est = (commonTotal / group) * kph * (1 - tripLoss)
        if not rate then return est end
        local h = rate.hours or 0
        return (est * 1 + rate.rate * h) / (1 + h)
      end)(),
      perHourMeasured = rate and rate.rate or nil, perHourIsEstimate = not rate,
      perHourTotal = (rate and rate.rate or (commonTotal / group) * kph * (1 - tripLoss)) * group, tripLoss = tripLoss, tripsPerHour = tripsPerHour,
      skinBasis = skinBasis, ctype = ctype, split = pf.split or 1, duo = pf.duo,
      npcPerHour = (coin + (own and own.pp > 0 and ownKills > 0 and own.ppCoin / ownKills or 0)) * kph,
      best = best, elite = elite,
    }
  end
  for npc in pairs(S.mobs) do build(npc) end
  for npc in pairs(lootNPCs()) do build(npc) end
  if C.settings.farmMetric == "common" then
    table.sort(rows, function(a, b) return a.perKillCommon > b.perKillCommon end)
  elseif opts.kind == "dungeon" or C.settings.farmMetric ~= "hour" then
    table.sort(rows, function(a, b) return a.perKill > b.perKill end)
  else
    table.sort(rows, function(a, b) if a.perHour ~= b.perHour then return a.perHour > b.perHour end return a.perKill > b.perKill end)
  end
  return rows, pending
end
