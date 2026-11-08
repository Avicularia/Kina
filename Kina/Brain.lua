-- Private Kina: the duo brain (Taylor's hunter + Ben's druid).
-- 1. Dungeons: every dungeon / elite area near your level, whether a hunter + druid
--    can duo it, what a run should pay at today's prices (drops, skins, disenchants),
--    and what YOUR runs actually paid. Estimates move toward your measured runs.
-- 2. Skill up: the cheapest way to level each of your crafting professions right
--    now: cost per skill point at today's prices, using the classic skill-up odds.
local ADDON, C = ...
local B = {}
C.Brain = B

------------------------------------------------------------------ duo levels
local function partnerLevel()
  if UnitExists and UnitExists("party1") then
    local l = UnitLevel and UnitLevel("party1"); if l and l > 0 then return l end
  end
  -- the last Kina partner we heard from
  local S = C.Share and C.Share.DB and C.Share.DB()
  local best
  for _, a in pairs(S and S.authors or {}) do
    if a.char and a.char.level and a.seen and C.Now() - a.seen < 7 * 86400 then
      if not best or a.seen > best.seen then best = a end
    end
  end
  return best and best.char.level or nil
end
function B.DuoLevel()
  local me = UnitLevel and UnitLevel("player") or 1
  local p = partnerLevel()
  return p and math.min(me, p) or me, me, p
end

-- How hard is an area for a hunter + druid at this level? (rules of thumb)
local function duoVerdict(eliteMax, eliteN, lvl)
  if eliteN == 0 then return 5, "|cff7CFC00easy|r", "no elites: normal mobs only" end
  local d = eliteMax - lvl
  if d <= -8 then return 5, "|cff7CFC00trivial|r", "elites are " .. -d .. " levels below you: pull whole packs" end
  if d <= -3 then return 4, "|cff7CFC00easy duo|r", "Ben tanks in bear form, your pet takes adds: pull 2-3 at a time" end
  if d <= 0 then return 3, "|cffffc94aduo with care|r", "elites at your level: single pulls, Ben ready to switch to healing" end
  if d <= 2 then return 2, "|cffff8040hard|r", "elites above you: one at a time, trap/hibernate the extras, expect deaths" end
  return 1, "|cffff4040not yet|r", "elites " .. d .. " levels above you: come back at level " .. (eliteMax - 1)
end

------------------------------------------------------------------ dungeons
local function measuredRuns(zone)
  local n, secs, net = 0, 0, 0
  for _, s in ipairs(C.db.sessions or {}) do
    if s.zone == zone then
      local g = s.gview or s.result
      local t = g and g.secs or 0
      local v = g and ((type(g.net) == "number" and g.net) or g.total) or 0
      if t and t > 120 then n = n + 1; secs = secs + t; net = net + v end
    end
  end
  return n, secs, net
end
function B.Dungeons()
  local lvl = B.DuoLevel()
  local lo, hi = math.max(1, lvl - 12), lvl + 6
  local rows = C.RankFarms({ kind = "dungeon", lo = lo, hi = hi }) or {}
  local by = {}
  for _, r in ipairs(rows) do
    local key = r.loc or r.zone or "?"
    local z = r.zone or (r.loc and ("area " .. r.loc)) or "?"
    local a = by[key]
    if not a then a = { zone = z, mobs = 0, elites = 0, eliteMax = 0, minL = 99, maxL = 0, perKillSum = 0, best = nil, bestV = 0, skins = 0 }; by[key] = a end
    a.mobs = a.mobs + 1
    if r.elite then a.elites = a.elites + 1; a.eliteMax = math.max(a.eliteMax, r.level or 0) end
    a.minL = math.min(a.minL, r.level or 99); a.maxL = math.max(a.maxL, r.level or 0)
    -- a typical clear kills each kind of mob several times
    local spawns = 4
    local f = r.npc and C.NPCFacts and C.NPCFacts(r.npc)
    if f and f.spawns and #f.spawns > 0 then spawns = math.min(15, #f.spawns) end
    local v = (r.perKillTotal or r.perKill or 0) * spawns
    a.perKillSum = a.perKillSum + v
    a.kills = (a.kills or 0) + spawns
    a.skins = a.skins + (r.skins or 0) * spawns
    if v > a.bestV then a.best, a.bestV = r, v end
  end
  local out = {}
  for key, a in pairs(by) do
    local z = a.zone
    if z:find("^area ") and a.best then z = "near " .. a.best.name; a.zone = z end
    -- dungeons, plus outdoor spots with 3+ kinds of elite (not a lone rare in a zone)
    local zi = type(key) == "number" and C.ZoneInfo and C.ZoneInfo(key)
    local instance = (zi and zi.inst and zi.inst > 0) or (type(key) == "number" and key < 0)
    if instance or a.elites >= 3 then
    local score, verdict, why = duoVerdict(a.eliteMax, a.elites, lvl)
    -- clear time estimate: ~25 s per elite kill, ~10 s per normal kill, +30% walking
    local estSecs = math.max(600, (a.kills or 0) * (a.elites > 0 and 25 or 10) * 1.3)
    local estHour = a.perKillSum * 3600 / estSecs
    local n, secs, net = measuredRuns(z)
    local hours = secs / 3600
    local measHour = hours > 0 and (net / hours) or nil
    local gph = measHour and ((estHour * 1 + measHour * hours) / (1 + hours)) or estHour
    local best = a.best and (a.best.name .. (a.best.best and C.Item(a.best.best) and C.Item(a.best.best).name and (": " .. C.Item(a.best.best).name) or "")) or "-"
    out[#out + 1] = { zone = z, score = score, verdict = verdict, why = why, levels = (a.minL < 99 and (a.minL .. "-" .. a.maxL) or "?"),
      elites = a.elites, eliteMax = a.eliteMax, run = a.perKillSum, estSecs = estSecs, gph = gph, measured = n, measHour = measHour,
      skins = a.skins, best = best, instance = instance }
    end
  end
  table.sort(out, function(x, y) if (x.score >= 3) ~= (y.score >= 3) then return x.score >= 3 end return x.gph > y.gph end)
  return out, lvl
end

------------------------------------------------------------------ skill up
-- classic odds: orange always, then (grey - skill) / (grey - yellow)
local function chance(r, skill)
  if not (skill and r.y and r.x) then return nil end
  if skill < r.y then return 1 end
  if skill >= r.x then return 0 end
  return math.max(0, math.min(1, (r.x - skill) / math.max(1, r.x - r.y)))
end
function B.SkillUp()
  local out = {}
  for prof, skill in pairs(C.char and C.char.prof or {}) do
    local rows = C.CraftRows and C.CraftRows({ prof = prof, mine = true }) or {}
    for _, r in ipairs(rows) do
      local p = chance(r, skill)
      local usable = r.status == "learned" or ((r.status == "can") and r.obtainable)
      if p and p > 0 and usable and r.cost then
        local resale = (r.value or 0) * 0.7 -- crafted leveling items don't all sell: count 70%
        local net = r.cost - resale
        out[#out + 1] = { prof = prof, skill = skill, r = r, p = p, cost = r.cost, value = r.value, net = net, perPoint = net / p,
          learn = r.status ~= "learned" and (r.learnCost or 0) or 0 }
      end
    end
  end
  table.sort(out, function(a, b) if a.prof ~= b.prof then return a.prof < b.prof end return a.perPoint < b.perPoint end)
  return out
end
