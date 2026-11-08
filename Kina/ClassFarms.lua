-- Kina: rogue and druid farm routes.
-- Sources, in order of trust:
--   your own data (kills, picks, chests you opened: always shown when present)
--   Forever guides: lockpicking (zockify.com/forever/rogue/lockpicking, Oct 2026),
--     gold methods (mmonster.co/wow-forever/guides/gold, Oct 2026)
--   Kina Scout's pickpocket research (Classic NPC leads, levels as published)
--   Classic knowledge for chest and node runs: treat as "go look" leads
-- Maps are Classic uiMapIDs (what the Forever client uses); x, y are area centres.
local _, C = ...
C.Data = C.Data or {}

-- class: "rogue" (rogue only), "both" (rogue or druid), "druid" (druid only)
-- druid: what a druid can do with that route (shown in the Druid column)
C.Data.classRoutes = {
  ---------------------------------------------------------------- lockpicking (rogue; skill = Lockpicking)
  { key = "lp-mill", kind = "Lockpick", class = "rogue", name = "Alther's Mill practice boxes", zone = "Redridge Mountains", map = 1433, x = 46.8, y = 45.1,
    lo = 16, hi = 30, skill = 1, skillTo = 90, faction = "Alliance", druid = "No (needs Pick Lock)",
    note = "Learn Pick Lock at level 16 (trainer quest gives Thieves' Tools). Rotate the practice lockboxes; Lucius's Lockbox needs 25.", src = "Forever lockpicking guide" },
  { key = "lp-ratchet", kind = "Lockpick", class = "rogue", name = "Pirate ship south of Ratchet", zone = "The Barrens", map = 1413, x = 65.1, y = 45.4,
    lo = 16, hi = 30, skill = 1, skillTo = 90, faction = "Horde", druid = "No (needs Pick Lock)",
    note = "Buccaneer's Strongboxes below deck. Do not open the Jewel of the Southsea casually.", src = "Forever lockpicking guide" },
  { key = "lp-lake", kind = "Lockpick", class = "rogue", name = "Lake Everstill footlockers (underwater)", zone = "Redridge Mountains", map = 1433, x = 39.8, y = 59.1,
    lo = 16, hi = 30, skill = 70, skillTo = 110, faction = "Both", druid = "No (Aquatic Form helps reach, but locked)",
    note = "Waterlogged Footlockers, skill 70. Surface before your breath runs out.", src = "Forever lockpicking guide" },
  { key = "lp-wet", kind = "Lockpick", class = "rogue", name = "Wetlands murloc camps (north of Menethil)", zone = "Wetlands", map = 1437, x = 20.3, y = 36.0,
    lo = 22, hi = 32, skill = 70, skillTo = 150, faction = "Both", druid = "No (needs Pick Lock)",
    note = "Battered Footlockers at 70 and 110. Murlocs come in groups; keep an escape route.", src = "Forever lockpicking guide" },
  { key = "lp-stone", kind = "Lockpick", class = "rogue", name = "Windshear Crag / Windshear Mine", zone = "Stonetalon Mountains", map = 1442, x = 66.1, y = 50.9,
    lo = 22, hi = 32, skill = 70, skillTo = 150, faction = "Both", druid = "No (needs Pick Lock)",
    note = "Venture Co. camps, mine boxes need 110. Humanoids: pick their pockets on the way.", src = "Forever lockpicking guide" },
  { key = "lp-durn", kind = "Lockpick", class = "rogue", name = "Durnholde Keep footlockers", zone = "Hillsbrad Foothills", map = 1424, x = 79.0, y = 44.5,
    lo = 24, hi = 34, skill = 70, skillTo = 150, faction = "Both", druid = "No (needs Pick Lock)",
    note = "Battered Footlockers at 70 and 110 inside a Syndicate keep: also a dense pickpocket circuit.", src = "Forever lockpicking guide" },
  { key = "lp-zoram", kind = "Lockpick", class = "rogue", name = "Zoram Strand coast", zone = "Ashenvale", map = 1440, x = 14.2, y = 16.2,
    lo = 22, hi = 32, skill = 70, skillTo = 115, faction = "Both", druid = "No (needs Pick Lock)",
    note = "Waterlogged Footlockers, mostly 70; naga patrols.", src = "Forever lockpicking guide" },
  { key = "lp-angor", kind = "Lockpick", class = "rogue", name = "Angor Fortress", zone = "Badlands", map = 1418, x = 41.3, y = 29.3,
    lo = 35, hi = 45, skill = 150, skillTo = 205, faction = "Both", druid = "No (needs Pick Lock)",
    note = "Battered (150) upstairs, Dented (175) below. Dark Iron dwarves 35-40: pick them too.", src = "Forever lockpicking guide" },
  { key = "lp-desolace", kind = "Lockpick", class = "rogue", name = "Sar'theris Strand underwater", zone = "Desolace", map = 1443, x = 36.6, y = 22.1,
    lo = 32, hi = 42, skill = 150, skillTo = 200, faction = "Both", druid = "No (needs Pick Lock)",
    note = "Waterlogged Footlockers, 150; long swims with naga.", src = "Forever lockpicking guide" },
  { key = "lp-slag", kind = "Lockpick", class = "rogue", name = "The Slag Pit", zone = "Searing Gorge", map = 1427, x = 40.0, y = 45.0,
    lo = 43, hi = 52, skill = 200, skillTo = 250, faction = "Both", druid = "No (needs Pick Lock)",
    note = "Dented Footlockers: lower tunnels from 200, upper from 225.", src = "Forever lockpicking guide" },
  { key = "lp-brd", kind = "Lockpick", class = "rogue", name = "Blackrock Depths door loop", zone = "Blackrock Mountain", map = 1427, x = 34.8, y = 84.8,
    lo = 56, hi = 60, skill = 280, skillTo = 300, faction = "Both", druid = "No (needs Pick Lock)",
    note = "Enter, pick the doors near the entrance, reset instances (5 per hour).", src = "Forever lockpicking guide" },
  { key = "lp-service", kind = "Service", class = "rogue", name = "Open lockboxes for tips", zone = "Stormwind / Ironforge", map = 1453, x = 62.5, y = 70.0,
    lo = 16, hi = 60, skill = 1, faction = "Both", druid = "No",
    note = "Advertise in Trade near the bank: they put the box in the 'will not be traded' slot, you open it, they tip. Skill-ups too.", src = "Forever lockpicking guide" },

  ---------------------------------------------------------------- pickpocket circuits (rogue). npc = mob to pick; data replaces the lead
  { key = "pp-cutpurse", kind = "Pick", class = "rogue", npc = 94, name = "Defias Cutpurse circuit", zone = "Elwynn Forest", map = 1429, x = 41.6, y = 52.8, lo = 5, hi = 8, druid = "No", note = "Practice circuit west and north of Goldshire.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-smuggler", kind = "Pick", class = "rogue", npc = 95, name = "Defias Smugglers, Molsen Farm", zone = "Westfall", map = 1436, x = 45, y = 40, lo = 11, hi = 14, druid = "No", note = "Smugglers throw daggers; trappers can net.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-footpad", kind = "Pick", class = "rogue", npc = 481, name = "Defias Footpads, farm circuit", zone = "Westfall", map = 1436, x = 50, y = 42, lo = 10, hi = 13, druid = "No", note = "Farm-to-farm loop near Sentinel Hill.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-riverpaw", kind = "Pick", class = "rogue", npc = 452, name = "Riverpaw Bandits", zone = "Westfall", map = 1436, x = 61, y = 70, lo = 15, hi = 18, druid = "No", note = "Bandit camps in southern Westfall.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-taskmaster", kind = "Pick", class = "rogue", npc = 98, name = "Riverpaw Taskmasters, Dust Plains", zone = "Westfall", map = 1436, x = 62, y = 72, lo = 16, hi = 19, druid = "No", note = "Bloodlust packs; pick and move on.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-durnholde", kind = "Pick", class = "rogue", npc = 2261, name = "Syndicate at Durnholde Keep", zone = "Hillsbrad Foothills", map = 1424, x = 79, y = 45, lo = 20, hi = 24, druid = "No", note = "Dense keep: pick everything, open the footlockers inside (70/110).", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-shadowhide", kind = "Pick", class = "rogue", npc = 433, name = "Shadowhide gnoll camps", zone = "Redridge Mountains", map = 1433, x = 75, y = 45, lo = 20, hi = 24, druid = "No", note = "Mixed camps in eastern Redridge.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-highway", kind = "Pick", class = "rogue", npc = 2586, name = "Syndicate Highwaymen, Northfold", zone = "Arathi Highlands", map = 1417, x = 32, y = 28, lo = 29, hi = 33, druid = "No", note = "Stealthed enemies can ambush you.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-sm", kind = "Pick", class = "rogue", npc = 4540, name = "Scarlet Monastery pick run", zone = "Tirisfal Glades", map = 1420, x = 84, y = 30, lo = 32, hi = 40, druid = "No", note = "Elite humanoids: pick only, sap and vanish; Forever's guide lists SM for pickpocketing.", src = "Kina Scout pickpocket research / Forever gold guide" },
  { key = "pp-wastewander", kind = "Pick", class = "rogue", npc = 5616, name = "Wastewander camps, Noonshade", zone = "Tanaris", map = 1446, x = 63, y = 29, lo = 40, hi = 45, druid = "No", note = "Sturdy Junkbox range; some rogues there are stealthed.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-rigger", kind = "Pick", class = "rogue", npc = 7855, name = "Southsea Pirates, Lost Rigger Cove", zone = "Tanaris", map = 1446, x = 72, y = 46, lo = 43, hi = 47, druid = "No", note = "Dense cove; footlockers (225) there later.", src = "Kina Scout pickpocket research (Classic lead)" },
  { key = "pp-brd", kind = "Pick", class = "rogue", npc = 8892, name = "Blackrock Depths pick run", zone = "Blackrock Mountain", map = 1427, x = 34.8, y = 84.8, lo = 52, hi = 60, druid = "No", note = "Heavy Junkboxes (250). Pick only, no kills needed.", src = "Forever lockpicking guide / Kina Scout research" },

  ---------------------------------------------------------------- stealth runs (rogue or druid)
  { key = "st-kurzen", kind = "Chest run", class = "both", name = "Kurzen compound chests", zone = "Stranglethorn Vale", map = 1434, x = 44, y = 10, lo = 30, hi = 36, druid = "Yes (Prowl)",
    note = "Humanoid camp with chests; stealth past patrols, pick on the way (rogue).", src = "Classic knowledge: verify" },
  { key = "st-stromgarde", kind = "Chest run", class = "both", name = "Stromgarde Keep ruins", zone = "Arathi Highlands", map = 1417, x = 22, y = 32, lo = 34, hi = 42, druid = "Yes (Prowl)",
    note = "Chests among Syndicate and elite ogres; herbs on the way for a druid.", src = "Classic knowledge: verify" },
  { key = "st-jintha", kind = "Chest run", class = "both", name = "Jintha'Alor terraces", zone = "The Hinterlands", map = 1425, x = 60, y = 75, lo = 45, hi = 52, druid = "Yes (Prowl)",
    note = "Elite trolls: stealth between chests; Vilebranch are humanoids (rogue picks).", src = "Classic knowledge: verify" },
  { key = "st-mara", kind = "Stealth nodes", class = "both", name = "Maraudon stealth herb/ore run", zone = "Desolace", map = 1443, x = 29, y = 62, lo = 45, hi = 60, druid = "Yes (Prowl, herbalist)",
    note = "Sneak past trash to the Gromsblood and ore inside; reset and repeat.", src = "Forever gold guide" },
  { key = "st-dme", kind = "Stealth nodes", class = "both", name = "Dire Maul East stealth run", zone = "Feralas", map = 1444, x = 59, y = 44, lo = 55, hi = 60, druid = "Yes (Prowl, herbalist)",
    note = "Stealth to the herbs and ore past the trash; Forever's guide lists it with Maraudon.", src = "Forever gold guide" },

  ---------------------------------------------------------------- druid (Aquatic Form, Prowl, Travel Form)
  { key = "dr-kelp", kind = "Underwater herbs", class = "druid", name = "Stranglekelp coasts", zone = "Westfall / Wetlands coasts", map = 1436, x = 30, y = 45, lo = 16, hi = 35, item = 3820, skill = 85,
    druid = "Best (Aquatic Form)", note = "Aquatic Form from level 16: unlimited breath and fast swimming. Stranglekelp grows only underwater; other classes run out of air.", src = "Classic knowledge: verify" },
  { key = "dr-clams", kind = "Underwater", class = "druid", name = "Giant clams for pearls", zone = "Great Sea coasts", map = 1434, x = 25, y = 30, lo = 20, hi = 45, item = 5500,
    druid = "Best (Aquatic Form)", note = "Underwater clams hold Small Lustrous / Iridescent / Black Pearls (crafting demand). Anyone can open them; a druid can stay down.", src = "Classic knowledge: verify" },
  { key = "dr-swiftthistle", kind = "Niche herb", class = "druid", name = "Swiftthistle for rogues", zone = "Mageroyal / Briarthorn zones", map = 1436, x = 50, y = 50, lo = 12, hi = 30, item = 2452, skill = 50,
    druid = "Yes (herbalist)", note = "Swiftthistle comes as a bonus from Mageroyal and Briarthorn. Rogues need it for Thistle Tea: list it when the price is up.", src = "Classic knowledge: verify" },
  { key = "dr-fadeleaf", kind = "Niche herb", class = "druid", name = "Fadeleaf for rogues", zone = "Swamp / Arathi / Hillsbrad", map = 1417, x = 40, y = 60, lo = 30, hi = 45, item = 3818, skill = 160,
    druid = "Yes (herbalist)", note = "Fadeleaf makes Blinding Powder, which rogues use constantly; Prowl helps in contested spots.", src = "Classic knowledge: verify" },
}

-- Junkbox tiers (Forever lockpicking guide; pickpocket drops by mob level, Classic ranges)
C.Data.junkboxes = {
  { id = 16882, name = "Battered Junkbox", skill = 1, lo = 20, hi = 30 },
  { id = 16883, name = "Worn Junkbox", skill = 70, lo = 30, hi = 40 },
  { id = 16884, name = "Sturdy Junkbox", skill = 175, lo = 40, hi = 50 },
  { id = 16885, name = "Heavy Junkbox", skill = 250, lo = 50, hi = 60 },
}

-- What a junkbox is worth to YOU: opened (if your Lockpicking can open it) at what
-- you have found inside them, otherwise what it sells for. Returns value, how.
function C.JunkboxValue(id)
  local j
  for _, x in ipairs(C.Data.junkboxes) do if x.id == id then j = x end end
  if not j then return nil end
  local mi = C.MarketItem(id)
  local sell = math.max(mi and mi.m and math.floor(mi.m * (1 - C.settings.ahCut)) or 0, C.VendorPrice(id) or 0)
  local lp = C.char.lockpicking or 0
  local b = C.db.boxes and C.db.boxes[id]
  if lp >= j.skill and b and b.n >= 3 then
    local v = b.coin
    for item, n in pairs(b.items) do local _, u = C.BestRoute(item, 1); v = v + (u or 0) * n end
    local opened = v / b.n
    if opened > sell then return opened, string.format("opened (%d seen)", b.n) end
  end
  if lp >= j.skill then return sell, "sell or open (open 3+ to measure)" end
  return sell, "sell (Lockpicking " .. j.skill .. " to open)"
end
local function isJunkbox(id) for _, x in ipairs(C.Data.junkboxes) do if x.id == id then return true end end end

-- Pickpocketing a mob, per pick: coin, items, junkboxes (valued opened or sold).
-- From your and shared pocket data; for an unpicked humanoid, a rough estimate.
function C.PickBreakdown(npc, farm)
  local P = C.Pockets
  local e = P and P.Combined(npc)
  if e and (e.picks or 0) > 0 then
    local coin, items, boxes, boxRate, how = 0, 0, 0, 0, nil
    local m = e.money
    if m and (m.count or 0) > 0 then coin = (m.total / m.count) * ((m.seen or m.count) / e.picks) end
    for id, it in pairs(e.items or {}) do
      local per = (it.qty or 0) / e.picks
      if isJunkbox(id) then
        local v, h = C.JunkboxValue(id); boxes = boxes + (v or 0) * per; boxRate = boxRate + per; how = h
      else
        local _, u = C.BestRoute(id, 1); if not u or u == 0 then u = C.VendorPrice(id) or 0 end
        items = items + u * per
      end
    end
    return { coin = coin, items = items, boxes = boxes, boxRate = boxRate, boxHow = how, total = coin + items + boxes, picks = e.picks }
  end
  if farm and farm.type == "Humanoid" then
    -- no pocket data: Classic pockets pay roughly half the corpse's coin
    local coin = (farm.coin or 0) * 0.5
    return { coin = coin, items = 0, boxes = 0, boxRate = 0, total = coin, picks = 0, estimated = true }
  end
end

------------------------------------------------------------------ class mode (per character)
-- Rogue or druid farms are shown for this character unless turned off with the
-- Farms tab toggle. Returns "ROGUE" / "DRUID" / nil, and the class.
function C.ClassMode()
  local cls = UnitClass and select(2, UnitClass("player"))
  if cls ~= "ROGUE" and cls ~= "DRUID" then return nil, cls end
  if C.char.classFarms == false then return nil, cls end
  return cls, cls
end

local KIND_ORDER = { Camp = 0, ["Pick+Kill"] = 1, Kill = 1, Pick = 2, Junkbox = 3, Lockpick = 4, Service = 5, ["Chest run"] = 6,
  ["Stealth nodes"] = 6, ["Underwater herbs"] = 7, Underwater = 7, ["Niche herb"] = 8 }
C.FarmKindOrder = KIND_ORDER

local function fits(r, L, lo, hi)
  -- show a route from 2 levels before it starts until it is outgrown
  return (r.lo or 1) <= math.max(hi, L) + 2 and (r.hi or 60) >= math.min(lo, L)
end

local function routeEvidence(r)
  if r.npc and C.Pockets then
    local e, mine = C.Pockets.Combined(r.npc)
    if e then return e.picks, mine end
  end
end

-- Rows for the Farms tab: kill farms plus this character's class farms.
-- opts: lo, hi (level band), kind ("world"|"dungeon"), mode ("ROGUE"|"DRUID"|nil)
function C.ClassFarmRows(opts)
  local P = C.Pockets
  local L = (UnitLevel and UnitLevel("player")) or 1
  local mode = opts.mode
  local rows, pending = C.RankFarms({ lo = opts.lo, hi = opts.hi, kind = opts.kind, all = opts.all, match = opts.match })
  local out = {}
  local pickSecs = 2.5            -- a pick before each kill costs about this much
  local pph = C.settings.picksPerHour or 120
  for _, r in ipairs(rows) do
    local row = { farm = r, npc = r.npc, kind = "Kill", name = r.name, level = r.level, perHour = r.perHour, per = r.perKill, perCommon = r.perKillCommon,
      perHourIsEstimate = r.perHourIsEstimate,
      evidence = (r.snapLoots and (r.snapLoots .. " base loots" .. ((r.ownKills or 0) > 0 and (" + " .. r.ownKills .. " your kills (" .. tostring(r.itemBasis) .. ")") or "")))
        or (r.ownKills .. " of your kills"), evidenceN = (r.snapLoots or 0) + (r.ownKills or 0), druid = "Yes", where = r.zone, best = r.best, measured = r.kphMeasured }
    if mode == "ROGUE" and opts.kind ~= "dungeon" then
      local pk = C.PickBreakdown(r.npc, r)
      if pk and pk.total > 0 then
        -- a pick before each kill (~2.5s) and ~5s to open each junkbox
        local kph = 3600 / (3600 / r.kph + pickSecs + pk.boxRate * 5)
        row.kind, row.pick = "Pick+Kill", pk.total
        row.per = r.perKill + pk.total / (r.group or 1)
        row.perCommon = (r.perKillCommon or 0) + pk.total / (r.group or 1)
        row.perHour = r.perHour -- measured farms already include your picks
        row.estimated = pk.estimated
        row.evidence = row.evidence .. (pk.picks > 0 and (", " .. pk.picks .. " picks") or ", pick estimate")
        row.druid = "Kill only"
        r.rogue = { coin = pk.coin, items = pk.items, boxes = pk.boxes, boxHow = pk.boxHow, total = pk.total,
          killOnlyHour = r.perHour, withHour = row.perHour, kph = kph, estimated = pk.estimated, picks = pk.picks }
        if pk.estimated then row.note = "Humanoid: pick estimate until you (or your party) pick it" end
      elseif r.type == "Humanoid" then
        row.note = "Humanoid: pick it first (no pocket data yet)"
      end
    end
    out[#out + 1] = row
  end
  -- starter farms: suggested before there's data, so players farm them and Kina learns
  if opts.kind ~= "dungeon" and C.Data.seedFarms then
    local have = {}
    for _, r in ipairs(out) do if r.npc then have[r.npc] = true end end
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    for _, sf in ipairs(C.Data.seedFarms) do
      local enemy = (sf.side == "A" and mine == "Horde") or (sf.side == "H" and mine == "Alliance")
      local inBand = not opts.lo or opts.all or (sf.lvl >= opts.lo and sf.lvl <= opts.hi)
      if not have[sf.npc] and inBand and (not enemy or C.settings.showEnemy) then
        local zone = C_Map and C_Map.GetAreaInfo and sf.area > 0 and select(2, pcall(C_Map.GetAreaInfo, sf.area)) or nil
        out[#out + 1] = { npc = sf.npc, kind = "Kill", name = sf.name, level = sf.lvl, seed = sf,
          evidence = "|cff7CFC00suggested|r: no data yet, farm it and Kina measures it", where = type(zone) == "string" and zone or "",
          note = "Worth farming for: " .. sf.why .. (sf.type == "Beast" and " (and leather if you skin)" or ""), druid = "Yes" }
      end
    end
  end
  -- camps: several mob types at one spot, as one row (open world only)
  if opts.kind ~= "dungeon" and C.CampRows then
    for _, row in ipairs(C.CampRows(opts)) do out[#out + 1] = row end
  end
  if not mode then return out, pending end

  local d = P.DB()
  local inRoute = {}
  -- rogue: pick-only rows from pocket data (yours and shared)
  if mode == "ROGUE" then
    local seen = {}
    local function addPick(npc, e)
      if seen[npc] then return end
      seen[npc] = true
      local all, mine, others = P.Combined(npc)
      if not all or all.picks < 5 then return end
      local own = C.db.loot[npc]
      local info = (own and own.lvl) and own or C.NPCInfo(npc)
      local lvl = info and info.lvl
      if lvl and (lvl < opts.lo - 3 or lvl > opts.hi + 3) then return end
      local pk = C.PickBreakdown(npc)
      local pv = pk and pk.total or P.ValuePerPick(npc, all)
      out[#out + 1] = { npc = npc, kind = "Pick", name = (all.name or (info and info.nm) or ("NPC " .. npc)), level = lvl,
        perHour = (C.MeasuredRate and (C.MeasuredRate(npc) or {}).rate) or 0, per = pv, estimated = true, evidence = string.format("%d picks (you %d%s)", all.picks, mine, others > 0 and (", +" .. others) or ""),
        druid = "No", where = (own and own.zone) or (info and info.zone) or "-", pockets = true }
      inRoute[npc] = true
    end
    for npc, e in pairs(d.loot) do addPick(npc, e) end
    for uid, a in pairs(d.shared) do if uid ~= d.uid then for npc, e in pairs(a.npcs or {}) do addPick(npc, e) end end end

    -- junkboxes in your bags
    local lp = C.char.lockpicking or 0
    for _, j in ipairs(C.Data.junkboxes) do
      local n = C.BagCount and C.BagCount(j.id) or 0
      if n > 0 then
        local mi = C.MarketItem(j.id)
        out[#out + 1] = { kind = "Junkbox", name = string.format("Open %d %s", n, j.name), level = j.lo, item = j.id,
          per = mi and mi.m, evidence = lp >= j.skill and "|cff40ff40you can open|r" or ("|cffff4040needs Lockpicking " .. j.skill .. "|r"),
          druid = "No", where = "your bags", junk = j, note = mi and ("Or sell: " .. C.Money(mi.m) .. " each on the AH") or "Not listed on the AH" }
      end
    end
  end

  -- curated routes for this class
  local lp = C.char.lockpicking or 0
  local lpCap = C.char.lockpickingMax or (L >= 16 and L * 5 or 0)
  for _, r in ipairs(C.Data.classRoutes) do
    local forMe = (r.class == "both") or (r.class == "rogue" and mode == "ROGUE") or (r.class == "druid" and mode == "DRUID")
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    if forMe and (not r.faction or r.faction == "Both" or r.faction == fac) and not (r.npc and inRoute[r.npc]) then
      local show, status = fits(r, L, opts.lo, opts.hi), nil
      if r.kind == "Lockpick" then
        show = L >= 16 and lp < (r.skillTo or 300) and r.skill <= math.max(lpCap, 1)
        if show then status = lp >= r.skill and "|cff40ff40now|r" or ("|cffffc54aat " .. r.skill .. "|r") end
      elseif r.kind == "Service" then
        show = L >= 16
      end
      if show then
        local row = { route = r, kind = r.kind, name = r.name, level = r.lo, druid = r.druid or "-", where = r.zone,
          evidence = status or (r.src and r.src:find("Forever") and "Forever guide" or "lead"), item = r.item, npc = r.npc }
        if r.kind == "Lockpick" then row.per = nil; row.perText = string.format("skill %d-%d", r.skill, r.skillTo or 300)
        elseif r.item then
          local mi = C.MarketItem(r.item)
          row.per = mi and mi.m
          row.perText = mi and (C.Money(mi.m) .. " " .. ((C.Item(r.item) and C.Item(r.item).name) or "")) or "not on AH"
        end
        local picks = routeEvidence(r)
        if picks then
          local pk = C.PickBreakdown(r.npc)
          local pv = pk and pk.total or P.ValuePerPick(r.npc)
          row.per = pv; row.perHour = (C.MeasuredRate and (C.MeasuredRate(r.npc) or {}).rate) or 0; row.estimated = true
          row.evidence = picks .. " picks"
        end
        out[#out + 1] = row
      end
    end
  end
  return out, pending
end

-- The three things worth doing right now, for the plan line.
function C.FarmPlan(rows)
  local best = {}
  local function take(pred)
    local pick
    for _, r in ipairs(rows) do
      if pred(r) and (not pick or (r.perHour or 0) > (pick.perHour or 0)) then pick = r end
    end
    return pick
  end
  local hour = C.settings.farmMetric == "hour"
  local money = hour and take(function(r) return r.perHour and r.perHour > 0 end)
  if not money then
    for _, r in ipairs(rows) do if r.per and r.per > 0 and (r.kind == "Kill" or r.kind == "Pick+Kill") and (not money or r.per > money.per) then money = r end end
  end
  if money then best[#best + 1] = money end
  -- lockpicking: the spot you can work now with the hardest locks (most skill-ups)
  local lock
  for _, r in ipairs(rows) do
    if r.kind == "Lockpick" and r.evidence and r.evidence:find("now") and (not lock or r.route.skill > lock.route.skill) then lock = r end
  end
  if lock then best[#best + 1] = lock end
  local junk = take(function(r) return r.kind == "Junkbox" and r.evidence:find("can open") end)
  if junk then best[#best + 1] = junk end
  if #best < 3 then
    local other = take(function(r) return r ~= money and (r.kind == "Chest run" or r.kind == "Stealth nodes" or r.kind == "Underwater herbs" or r.kind == "Niche herb") end)
    if other then best[#best + 1] = other end
  end
  return best
end


------------------------------------------------------------------ camps
-- Your changes to a camp (Edit mobs / Pin center here on its details), saved per camp:
-- C.db.campEdits[key] = { add = {npc=true}, drop = {npc=true}, pin = {map, x, y} }
function C.CampEdit(c, make)
  C.db.campEdits = C.db.campEdits or {}
  local e = C.db.campEdits[c.key]
  if not e and make then e = { add = {}, drop = {} }; C.db.campEdits[c.key] = e end
  return e
end
-- the camp's name (yours if you renamed it)
function C.CampName(c)
  local e = C.CampEdit(c)
  return (e and e.name and e.name ~= "") and e.name or c.name
end
-- the camp's mobs after your edits
function C.CampMobs(c)
  local e = C.CampEdit(c)
  if not e then return c.mobs end
  local out, seen = {}, {}
  for _, id in ipairs(c.mobs) do if not (e.drop and e.drop[id]) then out[#out + 1] = id; seen[id] = true end end
  for id in pairs(e.add or {}) do if not seen[id] then out[#out + 1] = id end end
  return out
end
-- Mobs that can't be skinned on Forever (seen in game), plus any you mark on a camp.
local NO_SKIN = { [428] = true, [442] = true, [505] = true } -- Dire Condor, Tarantula, Greater Tarantula (Taylor, 2026-10-17)
function C.NoSkin(npc)
  local mine = C.db and C.db.noSkin and C.db.noSkin[npc]
  if mine ~= nil then return mine end
  return NO_SKIN[npc] or false
end
-- One row per camp. Loot per kill = each mob's per kill, weighted by how often you
-- killed it there (your timed farms) or equally until you have. Gold/hour comes
-- only from timed farms where the camp's mobs were at least half the kills.
-- a farm belongs to a camp when it was started from the camp ("Farm this camp"), or
-- when it was in the camp's zone and the camp's mobs were at least half the kills
local function inCampFarm(s, c, set)
  if s.camp then return s.camp == c.key end
  if s.zone and c.zone and s.zone ~= c.zone then return false end
  local inCamp, all = 0, s.kills or 0
  for npc, k in pairs(s.byNpc or {}) do if set[npc] then inCamp = inCamp + k end end
  return all > 0 and inCamp / all >= 0.5
end
local function campMix(c)
  local set, kills, total = {}, {}, 0
  for _, id in ipairs(C.CampMobs(c)) do set[id] = true end
  for _, s in ipairs(C.db.sessions or {}) do
    if inCampFarm(s, c, set) then
      for npc, k in pairs(s.byNpc or {}) do if set[npc] then kills[npc] = (kills[npc] or 0) + k; total = total + k end end
    end
  end
  return kills, total
end
local function campRate(c)
  local set, income, secs, n = {}, 0, 0, 0
  for _, id in ipairs(C.CampMobs(c)) do set[id] = true end
  for _, s in ipairs(C.db.sessions or {}) do
    if s.result and (s.kills or 0) > 0 and inCampFarm(s, c, set) and (s.result.secs or 0) >= 300 then
      income = income + ((s.split and s.split.each) or s.result.total or 0); secs = secs + s.result.secs; n = n + 1
    end
  end
  if secs > 0 then return income * 3600 / secs, n end
end
function C.CampRows(opts)
  local camps = C.Data.camps or {}
  local want = {}
  for _, c in ipairs(camps) do for _, id in ipairs(C.CampMobs(c)) do want[id] = true end end
  local byNpc = {}
  for _, r in ipairs(C.RankFarms({ all = true, match = function(_, npc) return want[npc] end })) do byNpc[r.npc] = r end
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  local out = {}
  for _, c in ipairs(camps) do
    -- a camp you've farmed or edited always shows, even outside your level range
    local yours = C.CampEdit(c) ~= nil
    if not yours then for _, s in ipairs(C.db.sessions or {}) do if s.camp == c.key then yours = true; break end end end
    local overlap = not opts.lo or (c.hi >= opts.lo and c.lo <= opts.hi) or yours
    local z = C.ZoneInfo and C.ZoneInfo(c.area)
    local enemy = z and ((z.terr == 0 and mine == "Horde") or (z.terr == 1 and mine == "Alliance"))
    if (overlap or opts.all) and (not enemy or C.settings.showEnemy) then
      local kills, total = campMix(c)
      local per, common, wsum, parts = 0, 0, 0, {}
      for _, id in ipairs(C.CampMobs(c)) do
        local r = byNpc[id]
        if r then
          local w = total > 0 and (kills[id] or 0) / total or 1
          per = per + w * (r.perKill or 0); common = common + w * (r.perKillCommon or 0); wsum = wsum + w
          parts[#parts + 1] = { npc = id, name = r.name, level = r.level, per = r.perKill, common = r.perKillCommon, w = w, row = r,
            skins = (r.skins or 0) / (r.group or 1), beast = r.type == "Beast" and not C.NoSkin(id) }
        end
      end
      -- a camp with no mobs left (all taken out) still shows, so Edit mobs can bring them back
      local empty = wsum == 0
      if empty then wsum = 1 end
      do
        local rate, n = campRate(c)
        local ce = C.CampEdit(c)
        out[#out + 1] = { camp = c, campParts = parts, kind = "Camp", name = C.CampName(c), fav = ce and ce.fav or nil, level = c.lo == c.hi and c.lo or (c.lo .. "-" .. c.hi),
          per = per / wsum, perCommon = common / wsum, perHour = rate,
          evidence = (empty and #C.CampMobs(c) == 0 and "|cffff8040no mobs: open it, then Edit mobs to add some|r")
            or (empty and "|cff9d9d9dno kill data yet: farm it once and Kina measures it|r")
            or (#parts .. " mob types, " .. (total > 0 and (total .. " of your kills") or "equal mix (estimate)") .. (c.src == "C" and ", Classic guide" or "")),
          druid = "Yes", where = c.zone, note = c.note, measuredMix = total > 0, rateFarms = n }
      end
    end
  end
  return out
end


-- The middle of a camp: the densest patch of its mobs' spawn points in its zone
-- (spawn points from the NPC database ForeverVendors loads). map, x, y, points.
function C.CampCenter(c)
  local e = C.CampEdit(c)
  if e and e.pin and e.pin[1] then return e.pin[1], e.pin[2], e.pin[3], 0, 0, true end
  local pts = {}
  for _, id in ipairs(C.CampMobs(c)) do
    local f = C.NPCFacts and C.NPCFacts(id)
    for _, p in ipairs(f and f.spawns or {}) do
      local close = not c.near or (math.abs(p[2] - c.near[1]) <= (c.near[3] or 0.08) and math.abs(p[3] - c.near[2]) <= (c.near[3] or 0.08))
      if close and C.MapName and C.MapName(p[1]) == c.zone then pts[#pts + 1] = { p[1], p[2], p[3], id } end
    end
  end
  if #pts == 0 then return nil end
  -- the 8%-of-the-map square where the most of the camp's mob TYPES live together
  -- (then the most spawn points), so it lands on the camp, not on one mob's patch
  local best, bestScore = nil, -1
  for _, a in ipairs(pts) do
    local n, types, seen = 0, 0, {}
    for _, b in ipairs(pts) do
      if math.abs(a[2] - b[2]) <= 0.04 and math.abs(a[3] - b[3]) <= 0.04 then
        n = n + 1
        if not seen[b[4]] then seen[b[4]] = true; types = types + 1 end
      end
    end
    local score = types * 1000 + n
    if score > bestScore then best, bestScore = a, score end
  end
  local sx, sy, n = 0, 0, 0
  for _, b in ipairs(pts) do
    if math.abs(best[2] - b[2]) <= 0.04 and math.abs(best[3] - b[3]) <= 0.04 then sx, sy, n = sx + b[2], sy + b[3], n + 1 end
  end
  return best[1], sx / n, sy / n, n, #pts
end
