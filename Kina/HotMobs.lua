-- Kina: hot mobs (1.0.5). Which mobs you should never skip.
-- Taylor's rules (locked 2026-11-15):
--   * value = average gold PER KILL, never per hour: coin (only creatures that drop coin)
--     plus every drop that drops 15% or more x its price. Gear and crates never count.
--     An AH price only counts when 5+ are listed and it sells at least 20 an hour (a
--     market you can actually farm into; Taylor: "one an hour shouldn't make the hot
--     list"); otherwise the vendor price.
--   * a mob is compared with mobs within 3 levels of it, valued the same way; elites
--     only with elites.
--   * HOT (burning logo): the best in its zone, 2.5x the median mob of its level and
--     1.5x the top 10% of its level.
--   * KILL ON SIGHT (logo, no fire): top 3 in its zone, 2.5x the median, 1.3x the top 10%.
--   * rares, named mobs and anything with fewer than 5 spawn points never count.
--   * the logo is grey until Kina users have recorded 30 kills of it.
-- Where the numbers come from:
--   * Kina users' own kills (yours plus your guild's and party's, Share.lua): once a mob
--     has 100+ looted kills, its drop rates and coin come only from those.
--   * The private build also has Wowhead Forever's drop rates (DropData.lua) and spawn
--     points (HotSpawns.lua). The public build strips them (Wowhead's data can't be
--     redistributed), so there a mob needs 30+ Kina kills before it can be ranked.
local _, C = ...
local H = {}
C.Hot = H

H.RATE_MIN = 0.15
H.HOT_MED, H.HOT_TOP = 2.5, 1.5
H.KOS_MED, H.KOS_TOP = 2.5, 1.3
H.BAND = 3
H.KINA_KILLS = 30
H.MIN_SPAWNS = 5
H.MIN_SOLD = 20     -- sales per hour before an item's AH price counts
H.MIN_READINGS = 5  -- ...measured over at least this many pairs of AH scans (Taylor: don't
                    -- weight hot mobs with items we can't actually tell are selling)
H.CROWD_MIN = 30   -- Kina kills before a mob without Wowhead data is ranked at all
H.CROWD_RATES = 100 -- Kina kills before Kina's own drop rates replace Wowhead's
local TYPE_NUM = { Beast = 1, Dragonkin = 2, Demon = 3, Elemental = 4, Giant = 5, Undead = 6, Humanoid = 7, Critter = 8, Mechanical = 9 }

local COIN_TYPES = { [2] = true, [3] = true, [5] = true, [6] = true, [7] = true, [10] = true }
local TYPE_NAME = { [1] = "Beast", [2] = "Dragonkin", [3] = "Demon", [4] = "Elemental", [5] = "Giant", [6] = "Undead", [7] = "Humanoid", [8] = "Critter", [9] = "Mechanical", [10] = "Not specified" }
H.TYPE_NAME = TYPE_NAME

-- Wowhead zone (area) ID -> the game's map ID, for waypoints. WoW Forever's own new zones
-- are looked up through the NPC database addon (when installed) or Kina's kill records.
H.AREA_MAP = {
  [1] = 1426, [3] = 1418, [4] = 1419, [8] = 1435, [10] = 1431, [11] = 1437, [12] = 1429, [14] = 1411,
  [15] = 1445, [16] = 1447, [17] = 1413, [28] = 1422, [33] = 1434, [36] = 1416, [38] = 1432, [40] = 1436,
  [41] = 1430, [44] = 1433, [45] = 1417, [46] = 1428, [47] = 1425, [51] = 1427, [85] = 1420, [130] = 1421,
  [139] = 1423, [141] = 1438, [148] = 1439, [215] = 1412, [267] = 1424, [331] = 1440, [357] = 1444,
  [361] = 1448, [400] = 1441, [405] = 1443, [406] = 1442, [440] = 1446, [490] = 1449, [493] = 1450,
  [618] = 1452, [1377] = 1451,
}
function H.MapFor(area)
  if not area then return nil end
  if H.AREA_MAP[area] then return H.AREA_MAP[area] end
  local t = rawget(_G, "ForeverVendors_AreaToMap")
  return type(t) == "table" and t[area] or nil
end

------------------------------------------------------------------ coin
-- Coin per kill from Kina's own kill records (yours plus your guild's) once there are
-- 30+ looted kills; before that the level estimate (fitted to Kina kills at levels
-- 10-25 and Wowhead Forever's averages at 36-44; elites drop about 3.5x).
function H.CoinEstimate(level, ctype, elite)
  if not level or level < 1 or not COIN_TYPES[ctype or 7] then return 0 end
  local c = 36 * (level / 22) ^ 2.87
  return c * (elite and 3.5 or 1)
end
local function coinFor(npc, m)
  local rec = C.LootRecord and C.LootRecord(npc)
  local looted = rec and (rec.coinLoots or rec.looted or 0) or 0
  if rec and looted >= 30 and rec.coin then return rec.coin / looted, "Kina kills" end
  if m.money and m.money > 0 then return m.money, "Wowhead average" end
  return H.CoinEstimate(m.lvl, m.type, m.elite), "level estimate"
end

------------------------------------------------------------------ items
local CRATE = { "Crate", "Lockbox", "Strongbox", "Chest", "Coffer", "Footlocker", "Junkbox" }
local function isCrate(r)
  if not (r and r.name) then return false end
  for _, w in ipairs(CRATE) do if r.name:find(w) then return true end end
  return false
end
-- what one of this item is worth to a farmer, and how fast it sells
function H.ItemValue(id)
  local r = C.Item and C.Item(id)
  if r and (C.IsGear(r) or isCrate(r)) then return 0, "excluded" end
  local vend = (r and (r.vend or r.sell)) or 0
  local mi = C.MarketItem and C.MarketItem(id)
  local vel = C.market and C.market.vel and C.market.vel[id]
  local sold = (vel and (vel.n or 0) >= H.MIN_READINGS) and vel.v or 0
  local listed = mi and (mi.n or 0) or 0
  local ah = 0
  if mi and listed >= 5 and sold >= H.MIN_SOLD then
    local v, route = C.FarmValue(id)
    if route ~= "VENDOR" and route ~= "DISENCHANT" then ah = v or 0 end
  end
  if ah > vend then return ah, "AH", sold, listed end
  return vend, "vendor", sold, listed
end

------------------------------------------------------------------ the list
local cache, cacheAt
function H.Invalidate() cache = nil end

-- Wowhead mobs beyond the bundled snapshot (levels 36-44 so far)
local function extraMobs()
  return C.Data.hotExtra or {}
end

local function spawnsOf(npc)
  local s = C.Data.hotSpawns and C.Data.hotSpawns[npc]
  return s
end

-- a Kina kill record as a mob entry (drop counts per looted kill)
local function crowdMob(npc, rec)
  local looted = math.max(rec.looted or 0, 1)
  return { nm = rec.nm or ("NPC " .. npc), lvl = rec.lvl or 1, type = TYPE_NUM[rec.type or ""] or 10, elite = rec.elite and true or false,
    loots = looted, items = rec.items or {}, zoneName = rec.zone, crowd = true }
end

local function evaluate(npc, m)
  local coin, coinHow = coinFor(npc, m)
  local det = { { kind = "coin", value = coin, how = coinHow } }
  local total = coin
  for id, c in pairs(m.items or {}) do
    local rate = c / m.loots
    if rate >= H.RATE_MIN then
      local v, how, sold, listed = H.ItemValue(id)
      if v > 0 then
        det[#det + 1] = { kind = "item", id = id, rate = rate, price = v, value = rate * v, how = how, sold = sold, listed = listed }
        total = total + rate * v
      end
    end
  end
  table.sort(det, function(a, b) return a.value > b.value end)
  return total, det
end

function H.List()
  if cache and cacheAt and C.Now() - cacheAt < 600 then return cache end
  local S = C.DropSnapshot and C.DropSnapshot()
  local rows = {}
  local function add(npc, m)
    local rec = C.LootRecord and C.LootRecord(npc)
    local looted = rec and (rec.looted or 0) or 0
    -- Kina's own drop rates take over at 100+ looted kills
    if rec and looted >= H.CROWD_RATES then
      local cm = crowdMob(npc, rec)
      cm.nm = m and m.nm or cm.nm; cm.lvl = m and m.lvl or cm.lvl; cm.elite = (m and m.elite) or cm.elite; cm.loc = m and m.loc
      cm.money = m and m.money
      m = cm
    end
    if not m or m.boss then return end
    if not m.crowd and (m.loots or 0) < 300 then return end
    if m.crowd and looted < H.CROWD_MIN then return end
    local sp = spawnsOf(npc)
    if sp and (sp.n or 0) < H.MIN_SPAWNS then return end -- a named rare or quest mob, not a farm
    local total, det = evaluate(npc, m)
    local area = sp and sp.area or m.loc
    rows[#rows + 1] = { npc = npc, name = m.nm, lvl = m.lvl, elite = m.elite and true or false, type = m.type,
      area = area, zone = (area and H.ZoneName(area)) or m.zoneName or "?", value = total, det = det, loots = m.loots,
      source = m.crowd and "Kina" or "Wowhead",
      kinaKills = rec and math.max(rec.kills or 0, rec.looted or 0) or 0, spawn = sp }
  end
  local seen = {}
  -- the newer Wowhead pull (levels 30-44) wins over the October snapshot
  for npc, m in pairs(extraMobs()) do seen[npc] = true; add(npc, m) end
  for npc, m in pairs(S and S.mobs or {}) do if not seen[npc] then seen[npc] = true; add(npc, m) end end
  -- mobs only Kina users have data for (the whole list in the public build)
  for npc in pairs(C.LootNPCs and C.LootNPCs() or {}) do
    local rec = type(npc) == "number" and not seen[npc] and C.LootRecord and C.LootRecord(npc)
    if type(rec) == "table" then seen[npc] = true; add(npc, crowdMob(npc, rec)) end
  end
  -- compare: zone rank (same elite-ness), level band median and top 10%
  local byZone = {}
  for _, r in ipairs(rows) do
    local k = tostring(r.zone) .. (r.elite and "e" or "")
    byZone[k] = byZone[k] or {}
    table.insert(byZone[k], r)
  end
  for _, list in pairs(byZone) do
    table.sort(list, function(a, b) return a.value > b.value end)
    for i, r in ipairs(list) do r.rank, r.zoneN = i, #list end
  end
  for _, r in ipairs(rows) do
    local band = {}
    for _, x in ipairs(rows) do
      if x.elite == r.elite and math.abs(x.lvl - r.lvl) <= H.BAND then band[#band + 1] = x.value end
    end
    table.sort(band)
    local med = band[math.max(1, math.ceil(#band / 2))] or 1
    local top = band[math.max(1, math.floor(0.9 * (#band - 1)) + 1)] or 1
    r.xMed = r.value / math.max(10, med)
    r.xTop = r.value / math.max(10, top)
    local zoneOK = (r.zoneN or 0) >= 4
    if zoneOK and r.rank == 1 and r.xMed >= H.HOT_MED and r.xTop >= H.HOT_TOP then r.tier = "hot"
    elseif zoneOK and r.rank <= 3 and r.xMed >= H.KOS_MED and r.xTop >= H.KOS_TOP then r.tier = "kos" end
  end
  -- 1.0.6 (Taylor): the hot list that ships with Kina decides which mobs are hot (it's made
  -- from Taylor's scans, refreshed as often as we can). A listed mob shows the grey logo
  -- until YOU have killed it 30 times; then it lights up for you, a collectible. Its gold
  -- per kill stays hidden until then, and after that comes only from your own kills and
  -- loot, so it keeps changing as you farm. A mob taken off the list loses its logo.
  local HL = C.Data and C.Data.hotList
  if HL and HL.mobs and next(HL.mobs) and not H.ignoreList then
    -- 1.0.6: remember every listed mob, so one taken off the list goes to your archive
    C.db.hotSeen = type(C.db.hotSeen) == "table" and C.db.hotSeen or {}
    local hs = C.db.hotSeen
    for npc, e in pairs(HL.mobs) do
      local s = hs[npc] or {}
      s.nm, s.lvl, s.area, s.tier, s.elite, s.type = e.nm, e.lvl, e.area, e.tier, e.elite, e.type
      if not s.first then
        -- kills from before Kina knew it was hot count (it was hot then too)
        local own = C.db.loot and C.db.loot[npc]
        s.first, s.hk = C.Now(), type(own) == "table" and math.max(own.kills or 0, own.looted or 0) or 0
      end
      s.removed, s.frozenG = nil, nil -- (back on the list: its card grows again)
      hs[npc] = s
    end
    for npc, s in pairs(hs) do
      if not HL.mobs[npc] and not s.removed then
        -- off the list: its card freezes where it is
        s.removed = C.Now()
        s.frozenG = H.HotGold(npc, s)
      end
    end
    local have = {}
    for _, r in ipairs(rows) do
      local e = HL.mobs[r.npc]
      have[r.npc] = true
      r.tier, r.listed = e and e.tier or nil, e and true or nil
    end
    for npc, e in pairs(HL.mobs) do
      if not have[npc] then
        local area = e.area
        rows[#rows + 1] = { npc = npc, name = e.nm or ("mob " .. npc), lvl = e.lvl or 1, elite = e.elite and true or false, type = e.type,
          area = area, zone = (area and H.ZoneName(area)) or "?", value = 0, det = {}, loots = 0, source = "you",
          tier = e.tier, listed = true }
      end
    end
    for _, r in ipairs(rows) do
      if r.listed then
        local own = C.db.loot and C.db.loot[r.npc]
        local mine = type(own) == "table" and math.max(own.kills or 0, own.looted or 0) or 0
        r.kinaKills, r.mine = mine, mine
        if mine >= H.KINA_KILLS then
          local m = crowdMob(r.npc, own)
          local total, det = evaluate(r.npc, m)
          -- coin: what you actually looted per kill
          local coin = (own.coin or 0) / math.max(own.looted or 0, 1)
          total = total - ((det[1] and det[1].kind == "coin") and det[1].value or 0) + coin
          for _, d in ipairs(det) do if d.kind == "coin" then d.value, d.how = coin, "your kills" end end
          r.value, r.det, r.loots, r.source, r.hideValue = total, det, own.looted or 0, "you", nil
        else
          r.value, r.det, r.hideValue = 0, {}, true
        end
      end
    end
  end
  for _, r in ipairs(rows) do
    r.grey = r.tier and r.kinaKills < H.KINA_KILLS or false
  end
  cache, cacheAt = rows, C.Now()
  H.byNpc = {}
  for _, r in ipairs(rows) do H.byNpc[r.npc] = r end
  return rows
end

-- 1.0.6: card tiers by your kills (the card cosmetics read this when they arrive)
H.CARDS = { { key = "diamond", name = "Diamond", at = 5000 }, { key = "platinum", name = "Platinum", at = 1500 },
  { key = "gold", name = "Gold", at = 500 }, { key = "silver", name = "Silver", at = 100 },
  { key = "copper", name = "Copper", at = 15 }, { key = "base", name = "Base", at = 1 } }
function H.CardTier(kills)
  for _, c in ipairs(H.CARDS) do if (kills or 0) >= c.at then return c.key, c.name end end
  return nil
end

-- 1.0.6 (Taylor): a card only grows while its mob is hot. Kills while hot set the frame and
-- background; gold from it while hot sets the glow and animation. Off the list, it freezes.
H.GLOWS = { { key = "aura", at = 5000 * 10000 }, { key = "flames", at = 1000 * 10000 }, { key = "shimmer", at = 250 * 10000 },
  { key = "glow", at = 50 * 10000 }, { key = "faint", at = 10 * 10000 } } -- (copper; proposed, waiting on Taylor)
function H.GlowTier(gold)
  for _, g in ipairs(H.GLOWS) do if (gold or 0) >= g.at then return g.key end end
  return nil
end
-- a kill of yours: counts toward its card only while the mob is on the hot list
function H.CountKill(npc)
  local HL = C.Data and C.Data.hotList
  local s = C.db.hotSeen and C.db.hotSeen[npc]
  if s and not s.removed and HL and HL.mobs and HL.mobs[npc] then s.hk = (s.hk or 0) + 1 end
end
-- gold from it while hot: your total from it, in proportion to the kills made while hot
function H.HotGold(npc, s)
  s = s or (C.db.hotSeen and C.db.hotSeen[npc])
  if not s then return 0 end
  if s.removed and s.frozenG then return s.frozenG end
  local m = H.Mine(npc)
  if (m.kills or 0) <= 0 then return 0 end
  return m.total * math.min(1, (s.hk or 0) / m.kills)
end
-- a mob's card: { kills, gold, frame, frameName, glow, frozen } or nil if you have none
function H.Card(npc)
  local s = C.db.hotSeen and C.db.hotSeen[npc]
  if not s then return nil end
  local k = s.hk or 0
  local frame, frameName = H.CardTier(k)
  if not frame then return nil end
  local g = H.HotGold(npc, s)
  return { kills = k, gold = g, frame = frame, frameName = frameName, glow = H.GlowTier(g), frozen = s.removed and true or false }
end

-- what one mob has given you: kills, gold per kill (once you've lit it), total gold
-- (coin plus every drop at today's price), card
function H.Mine(npc)
  local own = C.db.loot and C.db.loot[npc]
  if type(own) ~= "table" then return { kills = 0, total = 0 } end
  local kills = math.max(own.kills or 0, own.looted or 0)
  local total = own.coin or 0
  for id, c in pairs(own.items or {}) do total = total + c * (H.ItemValue(id) or 0) end
  local per
  if kills >= H.KINA_KILLS then
    local total1, det = evaluate(npc, crowdMob(npc, own))
    local coin = (own.coin or 0) / math.max(own.looted or 0, 1)
    per = total1 - ((det[1] and det[1].kind == "coin") and det[1].value or 0) + coin
  end
  local card, cardName = H.CardTier(kills)
  return { kills = kills, per = per, total = total, card = card, cardName = cardName }
end

-- hot mobs taken off the list that you killed: newest removal first
function H.Archive()
  H.List()
  local out = {}
  for npc, s in pairs(C.db.hotSeen or {}) do
    if s.removed then
      local m = H.Mine(npc)
      if m.kills > 0 then
        local cd = H.Card(npc)
        out[#out + 1] = { npc = npc, name = s.nm or ("mob " .. npc), lvl = s.lvl or 1, zone = (s.area and H.ZoneName(s.area)) or "?",
          tier = s.tier, removed = s.removed, kills = m.kills, per = m.per, total = m.total,
          card = cd and cd.frame, cardName = cd and cd.frameName, glow = cd and cd.glow }
      end
    end
  end
  table.sort(out, function(a, b) return a.removed > b.removed end)
  return out
end

function H.ZoneName(area)
  if not area then return "?" end
  if C_Map and C_Map.GetAreaInfo then
    local ok, n = pcall(C_Map.GetAreaInfo, area)
    if ok and n and n ~= "" then return n end
  end
  local map = H.MapFor(area)
  local nm = map and C.MapName and C.MapName(map)
  return nm or ("zone " .. tostring(area))
end

function H.Info(npc)
  H.List()
  return H.byNpc and H.byNpc[npc]
end
function H.Tier(npc)
  local r = H.Info(npc)
  return r and r.tier, r and r.grey
end

-- Hot Farms tab: hot and kill-on-sight mobs near your level, best first; nil range =
-- every level. 1.0.5 (questing): it leans ahead, from 2 below you to `range` above (the
-- zones a guide sends you to next), since questers outlevel a zone fast.
function H.Farms(range)
  local L = (UnitLevel and UnitLevel("player")) or 1
  local out = {}
  for _, r in ipairs(H.List()) do
    if r.tier and (not range or (r.lvl >= L - 2 and r.lvl <= L + range)) then out[#out + 1] = r end
  end
  table.sort(out, function(a, b)
    if (a.tier == "hot") ~= (b.tier == "hot") then return a.tier == "hot" end
    return a.value > b.value
  end)
  return out
end

-- The middle of the thickest spawn: { map, x, y, inCamp, total, how } or nil.
-- Kina's own kill positions win once there are 30+ kills (that's where people farm);
-- then Wowhead's spawn points; then the NPC database addon.
function H.Spot(npc)
  local rec = C.LootRecord and C.LootRecord(npc)
  if rec and rec.locs and math.max(rec.kills or 0, rec.looted or 0) >= H.KINA_KILLS then
    local best, bm
    for map, p in pairs(rec.locs) do if type(p) == "table" and p.x and (not best or (p.n or 0) > (best.n or 0)) then best, bm = p, map end end
    if best then return { map = bm, x = best.x, y = best.y, inCamp = best.n, how = "where Kina users kill it" } end
  end
  local sp = spawnsOf(npc)
  if sp and sp.x then
    local map = H.MapFor(sp.area)
    if map then return { map = map, x = sp.x / 100, y = sp.y / 100, inCamp = sp.c, total = sp.n, how = "Wowhead spawn points" } end
    return { x = sp.x / 100, y = sp.y / 100, inCamp = sp.c, total = sp.n, how = "Wowhead spawn points", noMap = true }
  end
  local f = C.NPCFacts and C.NPCFacts(npc)
  if f and f.spawns and #f.spawns > 0 then
    local p = C.Nearest(f.spawns)
    if p then return { map = p[1], x = p[2], y = p[3], total = #f.spawns, how = "NPC database" } end
  end
  return nil
end

function H.Waypoint(npc)
  local r = H.Info(npc)
  local s = H.Spot(npc)
  if not s then C.Print("no spawn points known for this mob yet."); return false end
  if s.noMap then
    C.Print(string.format("no map pin for this zone yet; type: /way %s %.1f %.1f %s", r and r.zone or "?", s.x * 100, s.y * 100, r and r.name or ""))
    return false
  end
  return C.Waypoint(s.map, s.x, s.y, (r and r.name or "Hot mob") .. " (thickest spawn)")
end

------------------------------------------------------------------ nameplates
-- The burning Kina logo next to a hot mob's name. Kina's own frames sit on the
-- nameplate; nothing is stored on (or changed in) the game's nameplate frames.
local LOGO = "Interface\\AddOns\\Kina\\Media\\KinaLogo"
local FIRE = "Interface\\AddOns\\Kina\\Media\\UI\\hot_fire"
local pool, active = {}, {}
local FRAMES, FPS = 16, 16
local driver = CreateFrame("Frame")
local clock = 0
driver:Hide()
driver:SetScript("OnUpdate", function(_, dt)
  clock = clock + dt
  local k = math.floor(clock * FPS) % FRAMES
  local u, v = (k % 4) / 4, math.floor(k / 4) / 4
  for _, f in pairs(active) do if f.fire:IsShown() then f.fire:SetTexCoord(u, u + 0.25, v, v + 0.25) end end
end)
local function acquire()
  local f = table.remove(pool)
  if f then return f end
  f = CreateFrame("Frame")
  f:SetSize(22, 22)
  f.fire = f:CreateTexture(nil, "ARTWORK")
  f.fire:SetTexture(FIRE); f.fire:SetBlendMode("ADD")
  f.fire:SetSize(58, 58)
  f.logo = f:CreateTexture(nil, "OVERLAY")
  f.logo:SetTexture(LOGO); f.logo:SetAllPoints()
  -- the logo sits at the base of the flames (as in the approved mock)
  f.fire:SetPoint("CENTER", f.logo, "CENTER", 0, 58 * (0.725 - 0.5))
  -- 1.0.6: your gold per kill under the logo once you've lit it (30 of your kills)
  f.val = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.val:SetPoint("TOP", f.logo, "BOTTOM", 0, -1)
  return f
end
local function release(unit)
  local f = active[unit]
  if not f then return end
  active[unit] = nil
  f:Hide(); f:ClearAllPoints(); f:SetParent(nil)
  pool[#pool + 1] = f
  if not next(active) then driver:Hide() end
end
local function npcOf(unit)
  local g = UnitGUID and UnitGUID(unit)
  local id = g and select(6, strsplit("-", g))
  return tonumber(id)
end
local function show(unit)
  release(unit)
  if C.settings and C.settings.hotPlates == false then return end
  if IsInInstance and IsInInstance() then return end
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
  local npc = npcOf(unit)
  if not npc or UnitIsPlayer(unit) then return end
  local cls = UnitClassification and UnitClassification(unit)
  if cls == "rare" or cls == "rareelite" or cls == "worldboss" then return end
  local tier, grey = H.Tier(npc)
  if not tier then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then return end
  local f = acquire()
  local ok = pcall(function()
    f:SetParent(plate)
    f:SetFrameLevel((plate:GetFrameLevel() or 0) + 5)
    local uf = plate.UnitFrame
    local nameText = uf and uf.name
    if nameText and nameText.GetLeft then f:SetPoint("RIGHT", nameText, "LEFT", -2, 0)
    else f:SetPoint("BOTTOM", plate, "TOP", 0, 2) end
  end)
  if not ok then f:Hide(); pool[#pool + 1] = f; return end
  f.logo:SetDesaturated(grey and true or false)
  f.fire:SetDesaturated(grey and true or false)
  f.fire:SetAlpha(grey and 0.45 or 1)
  f.fire:SetShown(tier == "hot")
  local r = H.byNpc and H.byNpc[npc]
  if not grey and r and not r.hideValue and (r.value or 0) > 0 then f.val:SetText(C.Money(math.floor(r.value + 0.5))); f.val:Show()
  else f.val:SetText(""); f.val:Hide() end
  f:Show()
  active[unit] = f
  driver:Show()
end
function H.RefreshPlates()
  for unit in pairs(active) do release(unit) end
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken
    if unit then show(unit) end
  end
end
C.On("NAME_PLATE_UNIT_ADDED", function(_, unit) pcall(show, unit) end)
C.On("NAME_PLATE_UNIT_REMOVED", function(_, unit) release(unit) end)
-- prices change after a scan, kill counts change as the guild farms
C.On("INIT", function()
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(600, function() H.Invalidate(); pcall(H.RefreshPlates) end)
  end
end)
