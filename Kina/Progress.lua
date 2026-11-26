-- Kina 1.1.0: progression. Renown and Kina XP from farming: active minutes, the group's
-- gold, and gold per hour for your level. Only farms confirmed by at least one other
-- Kina count (Taylor: "solo farming does not add to your track, it must handshake with
-- at least one other Kina"). Every number comes from Season.lua.
--
--   per farm:  base   = perMinute x active minutes x pace
--              pace   = (group's loot / people) per hour / target for your level, 0.5x-3x
--              bonus  = party + streak + campfire share + track levels (all add up)
--              earned = base x (1 + bonus); each commendation later adds base x 10%
--   Quest gold, quest XP and quest items never count (they're on the widget and Ledger).
local _, C = ...
local P = {}
C.Progress = P
local function S() return C.Season end
local DAY = 86400

------------------------------------------------------------------ state
-- per season, so a new season starts every track (and its bonus) at zero
-- 2.0.19 (Taylor: "the streak needs to never die no matter what we do, even when we go into
-- a new season"): the streak lives outside the season, in the profile itself. The first time,
-- it takes the longest streak any season held.
function P.Streak()
  local d = C.db
  if type(d.streak) ~= "table" then
    local best
    for _, st in pairs(type(d.prog) == "table" and d.prog or {}) do
      local k = type(st) == "table" and st.streak
      if type(k) == "table" and k.last and (not best or (k.last or 0) > (best.last or 0)
        or ((k.last or 0) == (best.last or 0) and (k.days or 0) > (best.days or 0))) then best = k end
    end
    d.streak = best and { days = best.days or 0, half = best.half or false, halfRun = best.halfRun or 0, last = best.last }
      or { days = 0, half = false, halfRun = 0 }
  end
  return d.streak
end
function P.State(id)
  id = id or (S() and S().id) or "S1"
  C.db.prog = C.db.prog or {}
  local st = C.db.prog[id]
  if not st then
    st = { renown = 0, xp = 0, hours = 0, gold = 0, kills = {}, farms = {}, best = {} }
    C.db.prog[id] = st
  end
  st.kills = st.kills or {}; st.farms = st.farms or {}; st.best = st.best or {}
  st.streak = P.Streak() -- (saved as a copy in each season; always rebound to the one streak)
  return st
end

------------------------------------------------------------------ farm history
-- 2.0.19 (Taylor: "Hours farmed doesn't even make sense", "I only need one gold per hour
-- stat ... your share on your best farm"): one small line per farm, kept for good (the full
-- farms are trimmed to the last 50). Hours are clock time minus pauses, from farms of 15
-- minutes or more. Gold per hour is your own share: what you looted and were paid, per hour.
local MINFARM = 900
function P.Hist()
  C.db.farmHist = type(C.db.farmHist) == "table" and C.db.farmHist or {}
  return C.db.farmHist
end
-- 2.0.19 (Taylor: "On profile, on the Profession tracks I want to scroll over it and see how
-- much money I've made from that profession total. I also want this stat separated in each
-- session and searchable"): what each gathering profession brought in during a farm, from
-- its loot lines (skinned, gathered, fished, picked, opened), at today's prices. Crafting
-- isn't loot, so it has no line here.
local CTX_PROF = { skin = "Skinning", fish = "Fishing", pick = "Pick Pocketing", box = "Lockpicking" }
function P.ProfOf(e, lastNode)
  local ctx = e[5]
  if CTX_PROF[ctx] then return CTX_PROF[ctx] end
  if ctx ~= "node" then return nil end
  local G = C.Gather
  local n = lastNode and G and G.NODES and G.NODES[lastNode]
  if n and n[2] then return n[2] end
  local r = C.Item and C.Item(e[3])
  if r and r.cls == 7 and r.sub == 9 then return "Herbalism" end
  return "Mining"
end
function P.ProfIncome(s)
  local out = {}
  if type(s) ~= "table" or type(s.log) ~= "table" then return out end
  local lastNode
  for _, e in ipairs(s.log) do
    if e[2] == "opened" then lastNode = e[3]
    elseif e[2] == "loot" and not e[7] then
      local pr = P.ProfOf(e, lastNode)
      if pr then
        local each = (C.FarmValue and C.FarmValue(e[3], e[8])) or 0
        out[pr] = (out[pr] or 0) + math.floor(each * (e[4] or 1) + 0.5)
      end
    end
  end
  return out
end
-- every farm Kina remembers (the history keeps each farm's split): { [prof] = { total, farms, season, best, bestLabel } }
function P.ProfTotals()
  local out = {}
  local since = P.SeasonStart()
  local function add(pr, v, e)
    local x = out[pr] or { total = 0, farms = 0, season = 0, best = 0 }
    x.total, x.farms = x.total + v, x.farms + 1
    if (e.t or 0) >= since then x.season = x.season + v end
    if v > x.best then x.best, x.bestLabel = v, e.label end
    out[pr] = x
  end
  for _, e in pairs(P.Hist()) do
    if type(e) == "table" and type(e.prof) == "table" then for pr, v in pairs(e.prof) do if v > 0 then add(pr, v, e) end end end
  end
  if C.session then
    for pr, v in pairs(P.ProfIncome(C.session)) do if v > 0 then add(pr, v, { t = C.session.start, label = (C.session.label or "farm") .. " (now)" }) end end
  end
  return out
end

function P.HistAdd(s)
  if type(s) ~= "table" or not (s.start and s.stop) then return end
  local h = P.Hist()
  local key = tostring(math.floor(s.start))
  local secs = math.max(0, s.stop - s.start - (s.pausedSecs or 0))
  local gph = s.result and s.result.perHour
  if not gph and C.SessionSummary then local ok, sum = pcall(C.SessionSummary, s); gph = ok and sum and sum.perHour end
  local e = h[key] or {}
  e.t, e.secs, e.g = math.floor(s.start), math.floor(secs), s.groupN or 1
  e.gph = math.floor(tonumber(gph) or 0)
  e.kina = (s.sync or (s.prog and s.prog.score)) and true or e.kina
  e.label = s.label or s.zone or e.label
  local ok, pi = pcall(P.ProfIncome, s)
  if ok and next(pi) then e.prof = pi end
  h[key] = e
  return e
end
-- hours of farms 15+ minutes since a time: all, in a group, solo
function P.Hours(since)
  local all, grp, solo = 0, 0, 0
  for _, e in pairs(P.Hist()) do
    if type(e) == "table" and (e.secs or 0) >= MINFARM and (e.t or 0) >= (since or 0) then
      local hrs = e.secs / 3600
      all = all + hrs
      if (e.g or 1) >= 2 then grp = grp + hrs else solo = solo + hrs end
    end
  end
  return all, grp, solo
end
function P.SeasonStart() return (S() and S().startAt) or 0 end
-- your best share per hour this season, in gold (the banner); skip = a farm start to leave out
function P.BestGph(skip)
  local best, be = 0, nil
  for _, e in pairs(P.Hist()) do
    if type(e) == "table" and (e.secs or 0) >= MINFARM and (e.t or 0) >= P.SeasonStart() and e.t ~= skip then
      local g = (e.gph or 0) / 10000
      if g > best then best, be = g, e end
    end
  end
  return best, be
end
-- once: every farm still kept goes into the history, and the streak is rebuilt from the
-- days you farmed (15+ minutes) if that gives a longer one (Taylor wanted it retroactive)
function P.HistBackfill()
  local d = C.db
  for _, s in ipairs(d.sessions or {}) do if s ~= C.session then pcall(P.HistAdd, s) end end
  if d.streakRebuilt then return end
  d.streakRebuilt = C.Now()
  local days = {}
  for _, e in pairs(P.Hist()) do
    if type(e) == "table" and (e.secs or 0) >= MINFARM and e.t then
      days[math.floor((e.t - (C.DayOffset or 0)) / DAY)] = true
    end
  end
  local list = {}
  for dd in pairs(days) do list[#list + 1] = dd end
  table.sort(list)
  local k = { days = 0, half = false, halfRun = 0 }
  for _, dd in ipairs(list) do
    if not k.last then k.days, k.half, k.halfRun = 1, false, 0
    else
      local gap = dd - k.last
      if gap == 1 then
        k.days = k.days + 1
        if k.half then k.halfRun = (k.halfRun or 0) + 1; if k.halfRun >= 2 then k.half, k.halfRun = false, 0 end end
      elseif gap == 2 and not k.half then k.days, k.half, k.halfRun = k.days + 1, true, 1
      else k.days, k.half, k.halfRun = 1, false, 0 end
    end
    k.last = dd
  end
  local cur = P.Streak()
  if k.last and ((k.last > (cur.last or -1)) or (k.last == cur.last and (k.days or 0) > (cur.days or 0))) then
    cur.days, cur.half, cur.halfRun, cur.last = k.days, k.half, k.halfRun, k.last
  end
end

------------------------------------------------------------------ ladders
function P.Rank(renown)
  local ranks = S().ranks
  local r = 1
  for i, t in ipairs(ranks) do if (renown or 0) >= t.at then r = i end end
  return r, ranks[r], ranks[r + 1]
end
function P.Level(xp)
  local lv = 1
  for i, at in ipairs(S().levels) do if (xp or 0) >= at then lv = i end end
  return lv, S().levels[lv], S().levels[lv + 1]
end
local function tierOf(v, tiers)
  local n = 0
  for _, t in ipairs(tiers) do if (v or 0) >= t then n = n + 1 end end
  return n
end
P.TierOf = tierOf

-- the season's card mobs (a fixed list; the hot list stands in until it's picked)
function P.CardMobs()
  local s = S()
  if s.cardMobs then return s.cardMobs end
  local out = {}
  local list = C.Data and C.Data.hotList and C.Data.hotList.mobs
  if type(list) == "table" then for id in pairs(list) do out[#out + 1] = tonumber(id) end end
  table.sort(out)
  return out
end

-- every track: its level, its tier count, and exactly what's needed for the next tier
function P.Tracks(st)
  st = st or P.State()
  local out = {}
  for _, tr in ipairs(S().tracks) do
    local e = { id = tr.id, name = tr.name }
    if tr.id == "ring" then
      local r = P.Rank(st.renown)
      e.level, e.of = r, #S().ranks
      local nx = S().ranks[r + 1]
      e.next = nx and { need = nx.at - st.renown, what = "renown", to = "Rank " .. (r + 1) } or nil
    elseif tr.id == "stars" then
      local n = (C.Mentor and C.Mentor.Count and C.Mentor.Count()) or 0
      e.level, e.of = tierOf(n, tr.tiers), #tr.tiers
      local nx = tr.tiers[e.level + 1]
      e.next = nx and { need = nx - n, what = (nx - n == 1) and "recruit" or "recruits" } or nil
    elseif tr.id == "bond" then
      -- the Bond system as it is (Rep.lua), with your current partner
      local lvl = 0
      local n = C.SeasonGuide and C.SeasonGuide.Numbers and select(2, pcall(C.SeasonGuide.Numbers))
      if type(n) == "table" and C.Rep and C.Rep.BondLevel then lvl = C.Rep.BondLevel(n.bondCU or 0) end
      e.level, e.of = lvl, 20
      e.next = lvl < 20 and { need = 1, what = "bond level" } or nil
    elseif tr.id == "cards" then
      local lv, mobs, best = 0, P.CardMobs(), nil
      for _, id in ipairs(mobs) do
        local k = st.kills[id] or 0
        local t = tierOf(k, tr.tiers)
        lv = lv + t
        local nx = tr.tiers[t + 1]
        if nx and (not best or nx - k < best.need) then best = { need = nx - k, what = "kills", mob = id } end
      end
      e.level, e.of, e.next = lv, #mobs * #tr.tiers, best
    elseif tr.id == "banner" then
      local g = P.BestGph()
      e.level, e.of, e.value = tierOf(g, tr.tiers), #tr.tiers, g
      local nx = tr.tiers[e.level + 1]
      e.next = nx and { need = nx - g, what = "gold an hour", at = nx } or nil
    elseif tr.id == "hoard" then
      e.level, e.of, e.value = tierOf(st.gold, tr.tiers), #tr.tiers, st.gold
      local nx = tr.tiers[e.level + 1]
      e.next = nx and { need = nx - st.gold, what = "gold", at = nx } or nil
    end
    out[#out + 1] = e
  end
  return out
end
function P.TrackLevels(st)
  local n = 0
  for _, e in ipairs(P.Tracks(st)) do n = n + (e.level or 0) end
  return n
end
-- Master of Coin: every track at its top this season
function P.Complete(st)
  for _, e in ipairs(P.Tracks(st)) do if (e.of or 0) == 0 or (e.level or 0) < e.of then return false end end
  return true
end

------------------------------------------------------------------ streak
-- Taylor: +2% a day in a row (max +20%). Miss a day: half. Miss the next too: gone.
-- Two days in a row while at half: full again.
local function today() return math.floor((C.Now() - (C.DayOffset or 0)) / DAY) end
P.Today = today
function P.StreakBonus(st)
  st = st or P.State()
  local k = st.streak
  if not k.last then return 0 end
  local gap = today() - k.last
  local half = k.half or gap == 2
  if gap > 2 or (k.half and gap >= 2) then return 0 end
  local b = math.min(S().bonus.streakMax, (k.days or 0) * S().bonus.streakDay)
  return half and b / 2 or b
end
function P.NoteDay(st)
  local k, d = st.streak, today()
  if k.last == d then return end
  if not k.last then k.days, k.half, k.halfRun = 1, false, 0
  else
    local gap = d - k.last
    if gap == 1 then
      k.days = k.days + 1
      if k.half then k.halfRun = (k.halfRun or 0) + 1; if k.halfRun >= 2 then k.half, k.halfRun = false, 0 end end
    elseif gap == 2 and not k.half then k.days, k.half, k.halfRun = k.days + 1, true, 1
    else k.days, k.half, k.halfRun = 1, false, 0 end
  end
  k.last = d
end

------------------------------------------------------------------ during a farm
-- every minute: active (a kill, loot or gather in the last 3 minutes)? campfire on?
local lastAct = 0
function P.NoteActivity() lastAct = C.Now() end
function P.HasCampfire()
  local s = S()
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or not a then break end
      if a.spellId and s.campfireAuras[a.spellId] then return true end
      local n = type(a.name) == "string" and a.name:lower() or ""
      for _, pat in ipairs(s.campfireNames) do if n:find(pat, 1, true) then return true end end
    end
  elseif UnitBuff then
    for i = 1, 40 do
      local name, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
      if not name then break end
      if s.campfireAuras[id] then return true end
      local n = name:lower()
      for _, pat in ipairs(s.campfireNames) do if n:find(pat, 1, true) then return true end end
    end
  end
  return false
end
function P.Tick()
  local s = C.session
  if not s or s.paused then return end
  s.prog = s.prog or { act = 0, camp = 0 }
  if C.Now() - lastAct <= S().activeWindow then
    s.prog.act = s.prog.act + 1
    if P.HasCampfire() then s.prog.camp = s.prog.camp + 1 end
  end
end
local function loop() pcall(P.Tick); if C.After then C.After(60, loop) end end
if C.After then C.After(60, loop) end
for _, ev in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "LOOT_OPENED" }) do
  if C.On then C.On(ev, function() P.NoteActivity() end) end
end

------------------------------------------------------------------ at the end of a farm
-- the farm's other Kinas (from its shared log); none = it doesn't count
local function lower(s) return ((tostring(s or "")):match("^([^%-]+)") or tostring(s)):lower() end
function P.Members(s)
  local out, seen = {}, {}
  if not (s and s.sync and s.sync.chain) then return out, 0 end -- (2.0: was nil, which broke scoring)
  local others = {}
  for _, ev in ipairs(s.sync.chain) do
    local o = ev.origin and lower(ev.origin)
    if o then
      if ev.kind == "J" and not seen[o] then seen[o] = true; out[#out + 1] = ev.origin end
      others[o] = (others[o] or 0) + 1
    end
  end
  -- handshake: another member's own Kina wrote to the log (not just a join)
  local me = lower(UnitName and UnitName("player") or "")
  local confirmed = 0
  for o, n in pairs(others) do if o ~= me and n >= 2 then confirmed = confirmed + 1 end end
  return out, confirmed
end
-- 2.0.15 (Taylor: Renown is "Gold x Time x Commendations x Bond"): your Kina Partner in
-- the farm adds the bond bonus (+10%, growing to +20% with the bond)
function P.BondBonus(members)
  local Pa = C.Pair
  if not (Pa and Pa.IsPartner and Pa.Bonus) then return 0 end
  for _, who in ipairs(members or {}) do
    if Pa.IsPartner(who) then local ok, b = pcall(Pa.Bonus, who); return (ok and tonumber(b)) or 0 end
  end
  return 0
end
function P.Score(s, level)
  local cfg = S()
  local members, confirmed = P.Members(s)
  -- 2.0.6 (Taylor: "recheck all farms for progress enabling parameters and re-grant missed
  -- exp/renown"): farms from the 2.0 betas, when the Kina network wasn't reaching anyone and
  -- no shared log could form, count if you farmed them in a group and were together with
  -- the group for at least a third of the time (Kina's own together/apart tracking).
  if confirmed < 1 and s.rescore and (s.groupN or 0) >= 2 then
    local tog, apart = s.togetherTicks or 0, s.apartTicks or 0
    if tog > 0 and tog >= (tog + apart) / 3 then confirmed = 1 end
  end
  if confirmed < 1 then return nil, "solo" end
  -- 2.0.15 (Taylor: "we just got exp and commendations for a 13:41 farm, it shouldn't award
  -- anything until 15 minutes"): a farm earns nothing under 15 minutes on the clock (pauses
  -- don't count), the same line commendations use
  if s.stop and s.start and (s.stop - s.start - (s.pausedSecs or 0)) < 900 then return nil, "short" end
  local mins = (s.prog and s.prog.act) or 0
  if mins < 1 then return nil, "idle" end
  local people = math.max(2, #members)
  -- the whole group's loot (never quest rewards); everyone gets credit for all of it
  local groupLoot = (s.split and s.split.total) or (s.gview and s.gview.net) or 0
  local perHour = groupLoot / people / (mins / 60)
  -- 2.0 (approved Nov 21): pace compares the whole group's gold per hour with the target, the
  -- same way everyone gets credit for every drop
  local groupPerHour = groupLoot / (mins / 60)
  local pace = groupPerHour / cfg.Target(level or (UnitLevel and UnitLevel("player")) or 1)
  pace = math.max(cfg.pace.min, math.min(cfg.pace.max, pace))
  local base = cfg.perMinute * mins * pace
  local b = cfg.bonus
  local st = P.State()
  local parts = {
    party = math.min(b.partyMax, b.partyEach * (people - 1)),
    streak = P.StreakBonus(st),
    campfire = b.campfire * ((s.prog and s.prog.camp or 0) / mins),
    tracks = b.trackLevel * P.TrackLevels(st),
    bond = P.BondBonus(members),
  }
  local bonus = 0
  for _, v in pairs(parts) do bonus = bonus + v end
  return { base = base, bonus = bonus, parts = parts, earned = math.floor(base * (1 + bonus) + 0.5),
    mins = mins, pace = pace, perHour = perHour, groupLoot = groupLoot, people = people,
    kills = (s.gview and s.gview.kills) or s.kills or 0 }
end

-- credit one finished farm (once). Returns the score, or nil and why it didn't count.
function P.Credit(s, quiet)
  if not s or s.progCredited then return nil, "done" end
  -- scored at the level you farmed it (2.0.6), not the level you are now
  local sc, why = P.Score(s, s.maxLvl or s.lvl)
  s.progCredited = true
  if not sc then s.progWhy = why; return nil, why end
  local st = P.State()
  P.NoteDay(st)
  local before = { rank = P.Rank(st.renown), level = P.Level(st.xp) }
  st.renown = st.renown + sc.earned
  st.xp = st.xp + sc.earned
  st.hours = st.hours + sc.mins / 60
  st.gold = st.gold + sc.groupLoot / 10000
  -- card kills: the group's kills of each card mob in this farm
  for id, n in pairs(s.groupKills or {}) do st.kills[id] = (st.kills[id] or 0) + n end
  local ref = (s.sync and s.sync.sid) or ("t" .. tostring(s.start))
  st.farms[ref] = { base = sc.base, t = C.Now(), commends = 0 }
  pcall(applyPending, st, ref)
  -- bests for the leaderboards
  st.best.perHour = math.max(st.best.perHour or 0, sc.perHour)
  -- 2.0.19: the banner is your own share per hour on your best farm this season (in gold);
  -- (groupGph keeps its old name in the recap: it is this farm's share per hour now)
  sc.bannerBefore = P.BestGph(s.start and math.floor(s.start))
  local he = P.HistAdd(s)
  local gph = he and (he.gph or 0) / 10000 or 0
  st.best.groupGph = math.max(sc.bannerBefore, gph)
  sc.groupGph = gph
  st.best.farm = math.max(st.best.farm or 0, sc.groupLoot)
  -- old farm records go after 3 days (commendations come within 2)
  for k, f in pairs(st.farms) do if C.Now() - (f.t or 0) > 3 * DAY then st.farms[k] = nil end end
  sc.rankUp = P.Rank(st.renown) > before.rank and P.Rank(st.renown) or nil
  sc.levelUp = nil -- 2.0.14: one ladder (Renown); the rank-up is the level-up
  s.prog = s.prog or {}; s.prog.score = sc
  -- 2.0.5 (Taylor: XP came in but the recap never showed): a failure is said, not hidden,
  -- and /kina recap opens it again
  if C.FarmRecap and not quiet then
    local ok, e = pcall(C.FarmRecap, s, sc)
    if not ok then
      if C.LogError then C.LogError("farm recap", e) end
      C.Print("|cffff8060the farm recap couldn't open (" .. tostring(e) .. "). /kina recap tries again; tell Claude what it says.|r")
    end
  end
  return sc
end

-- a commendation for one of your farms: +10% of that farm's base
-- 2.0 (Taylor: "it only gave 10 rep and no multiplier that I can see"): each commendation
-- is +10% of that farm's Renown and Kina XP. One that arrives before your Kina has scored
-- the farm waits for it (st.pending) instead of being lost; a farm that earned nothing
-- (nobody else's Kina joined) gives nothing, and the toast says so.
function P.OnCommend(ref)
  local st = P.State()
  if not ref or ref == "" then return nil, "nofarm" end
  local f = st.farms[ref]
  if not f then
    -- was it scored and earned nothing, or not scored yet?
    for _, s in ipairs(C.db.sessions or {}) do
      local r = (s.sync and s.sync.sid) or ("t" .. tostring(s.start))
      if r == ref and s.progCredited then return nil, "noearn" end
    end
    st.pending = st.pending or {}
    st.pending[ref] = (st.pending[ref] or 0) + 1
    return nil, "pending"
  end
  local add = math.floor(f.base * S().bonus.commend + 0.5)
  f.commends = (f.commends or 0) + 1
  st.renown = st.renown + add; st.xp = st.xp + add
  return add
end
-- commendations that came before the farm was scored
local function applyPending(st, ref)
  local n = st.pending and st.pending[ref]
  if not n then return 0 end
  st.pending[ref] = nil
  local total = 0
  for _ = 1, n do total = total + (P.OnCommend(ref) or 0) end
  if total > 0 and C.Print then C.Print(string.format("|cff4fc3f7commendations for this farm: +%d Renown (+10%% each).|r", total)) end
  return total
end

-- hooks: farm end, kills of card mobs, commendations
local origEnded = C.FarmEnded
C.FarmEnded = function(s, ...)
  -- 2.0: an error in an older farm-end step never stops the season credit
  if origEnded then local ok, e = pcall(origEnded, s, ...); if not ok and C.LogError then C.LogError("farm end", e) end end
  pcall(P.HistAdd, s) -- 2.0.19: every farm, counted or not, goes into the history
  local ok, sc, why = pcall(P.Credit, s)
  if not ok and C.LogError then C.LogError("season credit", sc) end
  -- no credit: say why, once, so a farm never quietly earns nothing
  if ok and not sc and C.Print and why ~= "done" then
    local msg = ({
      solo = "no Renown for this farm: nobody else's Kina joined it. Farms count when at least one other Kina joins (they answer the join popup).",
      short = "no Renown for this farm: farms count from 15 minutes.",
      idle = "no Renown for this farm: Kina saw no farming in it.",
    })[why]
    if msg then C.Print(msg) end
  end
end
-- a kill: activity, and (shared farms) the group's card-mob tally
function P.NoteKill(npcId)
  P.NoteActivity()
  local s = C.session
  if not (s and npcId) then return end
  s.groupKills = s.groupKills or {}
  s.groupKills[npcId] = (s.groupKills[npcId] or 0) + 1
end
if C.Vouch and C.Vouch.OnVouch then
  local orig = C.Vouch.OnVouch
  C.Vouch.OnVouch = function(from, kind, ref)
    local d = C.db.vouch and C.db.vouch.got
    local n = d and #d or 0
    -- the toast is shown here, with what the commendation is worth in 2.0
    C.Vouch.quietToast = true
    local r = orig(from, kind, ref)
    C.Vouch.quietToast = nil
    local after = C.db.vouch and C.db.vouch.got
    if after and #after > n then
      local g = after[#after]
      local bad = C.Vouch.IsBad(kind)
      local add, why
      if not bad then
        local ok, a, w = pcall(P.OnCommend, ref)
        if ok then add, why = a, w end
      end
      if C.Toast and C.Toast.Commended then
        pcall(C.Toast.Commended, g.who, C.Vouch.KINDS[tonumber(kind) or 1], bad, add, why)
      end
    end
    return r
  end
end

------------------------------------------------------------------ for the screens
-- big numbers stay short, so the plate never needs updating: 842g, 12.4k, 1.25m
function P.ShortGold(g)
  g = tonumber(g) or 0
  local a = math.abs(g)
  if a < 1000 then return string.format("%dg", math.floor(g + 0.5)) end
  if a < 1e6 then return string.format(a < 1e4 and "%.2fk" or (a < 1e5 and "%.1fk" or "%.0fk"), g / 1e3) end
  if a < 1e9 then return string.format(a < 1e7 and "%.2fm" or (a < 1e8 and "%.1fm" or "%.0fm"), g / 1e6) end
  return string.format("%.2fb", g / 1e9)
end
P.QCOLOR = { poor = "|cff9d9d9d", common = "|cffffffff", uncommon = "|cff1eff00", rare = "|cff0070dd",
  epic = "|cffa335ee", legendary = "|cffff8000", artifact = "|cffe6cc80" }
-- 2.0.14 (Taylor: "multiple tracks... not really any indication as to what rank is for
-- what"; chose one ladder): Kina level is gone as a separate number. Renown is the one
-- ladder; its rank is the number on the portrait ring and the title after the name.
-- A player's ring number from what their Kina shares (their season Renown), or nil.
function P.RingOf(pr)
  if pr and pr.season and pr.season.renown then return (P.Rank(pr.season.renown)) end
  return nil
end
-- the one Renown panel line set: bar fill (within this rank), bar label (totals),
-- and the "what it is / what's next" lines
function P.RenownView(renown)
  local function nn(v) v = math.floor((v or 0) + 0.5); return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v) end
  local r, cur, nx = P.Rank(renown)
  local fill = nx and math.max(0, math.min(1, ((renown or 0) - cur.at) / math.max(1, nx.at - cur.at))) or 1
  local label = nx and string.format("%s / %s Renown", nn(renown), nn(nx.at)) or (nn(renown) .. " Renown (top rank)")
  local what = string.format("%sRank %d %s|r|cff9d9d9d: the number on the ring and the title after the name.|r",
    P.QCOLOR[cur.q] or "", r, cur.title)
  local nextLine = nx and string.format("|cff9d9d9dNext:|r %sRank %d %s|r|cff9d9d9d at %s (%s to go). Earned by farming with other Kina users.|r",
    P.QCOLOR[nx.q] or "", r + 1, nx.title, nn(nx.at), nn(nx.at - (renown or 0)))
    or "|cff6ee678Top rank this season.|r"
  return fill, label, what, nextLine, r
end
-- 2.0.14: hover text for your Renown (widget plate)
function C.RenownTip()
  if not GameTooltip then return end
  local st = P.State()
  local _, label, what, nextLine = P.RenownView(st.renown)
  GameTooltip:AddLine("Renown")
  GameTooltip:AddLine(label, 1, 1, 1)
  GameTooltip:AddLine(what, 1, 1, 1, true)
  GameTooltip:AddLine(nextLine, 1, 1, 1, true)
end
function P.RankText(st)
  st = st or P.State()
  local r, t = P.Rank(st.renown)
  return (P.QCOLOR[t.q] or "") .. "Rank " .. r .. "  " .. t.title:gsub("^%l", string.upper) .. "|r", r, t
end
function P.PerHour(st)
  st = st or P.State()
  return st.hours > 0.05 and st.gold / st.hours or 0
end
-- the gold plate: gold farmed or gold per hour (the player picks; click the plate)
function P.PlateText(st)
  st = st or P.State()
  local o = C.db.opts or {}
  if o.platePerHour then return P.ShortGold(P.PerHour(st)) .. "/hr", "gold per hour" end
  return P.ShortGold(st.gold), "gold farmed"
end
function P.TogglePlate()
  C.db.opts = C.db.opts or {}
  C.db.opts.platePerHour = not C.db.opts.platePerHour
  if C.Refresh then C.Refresh() end
end
-- the bonus a farm would get right now (party counted when it happens)
function P.BonusNow(st)
  st = st or P.State()
  return P.StreakBonus(st) + S().bonus.trackLevel * P.TrackLevels(st)
end
-- the old standing ring art stands in for each rank until the season art is made
P.RING_ART = { "Unproven", "Unproven", "Vouched", "Vouched", "Reliable", "Trusted", "Honored", "Revered", "Exalted", "Exalted" }

------------------------------------------------------------------ the farm-complete recap
-- Taylor: "give it lots of dopamine". The breakdown of what this farm earned, and a
-- fanfare flyout when it crossed a Kina level or a Renown rank.
local GOLDC, GREYC, GREENC = "|cffffc54a", "|cff9d9d9d", "|cff40ff40"
local function num(v) v = math.floor((v or 0) + 0.5); return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v) end
local recap
local function buildRecap()
  if recap then return recap end
  -- 2.0.15 (Taylor: "a LOT of popups after a farm, I need them to all be in one window"):
  -- one Farm complete window: what you earned (gold, XP, Renown and the three season
  -- tracks), who commended you, and the commend cards for your partners, with one Done
  local f = CreateFrame("Frame", "KinaFarmRecap", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(640, 330); f:SetPoint("CENTER", 0, 120)
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(120); f:SetClampedToScreen(true)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.97); f:SetBackdropBorderColor(0.86, 0.6, 0.2, 1)
  end
  if C.Skin and C.Skin.Rivets then pcall(C.Skin.Rivets, f) end
  -- the title on its plate
  local SC = C.Showcase
  f.head = SC and SC.Plate(f, "name", 300, 44)
  if f.head then f.head:SetPoint("TOP", 0, 14); f.head:SetFrameLevel(f:GetFrameLevel() + 5) end
  f.title = (f.head or f):CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("CENTER", f.head or f, f.head and "CENTER" or "TOP", 0, f.head and 1 or -14)
  if C.Cos and C.Cos.Font then C.Cos.Font(f.title, 18, "OUTLINE") end
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.sub:SetPoint("TOP", 0, -36)
  local function panel(x, y, w, h, title)
    local p = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    p:SetPoint("TOPLEFT", x, y); p:SetSize(w, h)
    if p.SetBackdrop then
      p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
      p:SetBackdropColor(0.1, 0.075, 0.045, 0.95); p:SetBackdropBorderColor(0.55, 0.4, 0.15, 1)
    end
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); p.title:SetPoint("TOPLEFT", 10, -8); p.title:SetText(GOLDC .. title .. "|r")
    return p
  end
  -- what you earned
  f.earn = panel(14, -54, 384, 262, "What you earned")
  f.rows = {}
  for i = 1, 4 do
    local y = -28 - (i - 1) * 24
    local ic = f.earn:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18); ic:SetPoint("TOPLEFT", 10, y + 2)
    local l = f.earn:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", 34, y); l:SetJustifyH("LEFT")
    local r = f.earn:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r:SetPoint("TOPRIGHT", -10, y); r:SetJustifyH("RIGHT")
    f.rows[i] = { l, r, ic }
  end
  f.why = f.earn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.why:SetPoint("TOPLEFT", 34, -122); f.why:SetPoint("RIGHT", -10, 0); f.why:SetJustifyH("LEFT")
  local sep = f.earn:CreateTexture(nil, "ARTWORK"); sep:SetColorTexture(0.55, 0.4, 0.15, 0.6); sep:SetHeight(1); sep:SetPoint("TOPLEFT", 10, -140); sep:SetPoint("TOPRIGHT", -10, -140)
  f.tracks = {}
  for i = 1, 3 do
    local y = -148 - (i - 1) * 37
    local l = f.earn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); l:SetPoint("TOPLEFT", 10, y); l:SetJustifyH("LEFT")
    local r = f.earn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r:SetPoint("TOPRIGHT", -10, y); r:SetJustifyH("RIGHT")
    local bg = f.earn:CreateTexture(nil, "ARTWORK"); bg:SetColorTexture(0, 0, 0, 0.9); bg:SetPoint("TOPLEFT", 10, y - 15); bg:SetPoint("TOPRIGHT", -10, y - 15); bg:SetHeight(8)
    local fill = f.earn:CreateTexture(nil, "ARTWORK", nil, 1); fill:SetPoint("TOPLEFT", bg, "TOPLEFT"); fill:SetHeight(8)
    local n = f.earn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); n:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 0, -2); n:SetJustifyH("LEFT")
    f.tracks[i] = { l = l, r = r, bg = bg, fill = fill, n = n }
  end
  -- who commended you
  f.got = panel(410, -54, 216, 262, "You were commended")
  f.gotText = f.got:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.gotText:SetPoint("TOPLEFT", 10, -30); f.gotText:SetPoint("RIGHT", -10, 0)
  f.gotText:SetJustifyH("LEFT"); f.gotText:SetJustifyV("TOP"); f.gotText:SetSpacing(4)
  f.gotLines = {}
  -- the commend cards dock under both panels (Vouch.lua)
  f.slot = CreateFrame("Frame", nil, f); f.slot:SetPoint("TOPLEFT", 14, -322); f.slot:SetPoint("TOPRIGHT", -14, -322); f.slot:SetHeight(1)
  f.banner = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.banner:SetPoint("TOP", f.sub, "BOTTOM", 0, -2)
  local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); ok:SetSize(130, 26); ok:SetPoint("BOTTOM", 0, 12); ok:SetText("Done")
  if C.Skin then C.Skin.Button(ok) end
  f.doneNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.doneNote:SetPoint("BOTTOM", ok, "TOP", 0, 3)
  ok:SetScript("OnClick", function() f:Hide() end)
  f:SetScript("OnHide", function(self)
    if self.docked then local d = self.docked; self.docked = nil; d:Hide() end
    self.gotLines = {}
  end)
  -- (no Escape: when commend cards are in it, Done is what closes them)
  f:Hide()
  recap = f
  return f
end
local function relayoutRecap(f)
  local extra = f.docked and (f.docked:GetHeight() + 8) or 0
  f:SetHeight(330 + extra + (f.docked and 18 or 22))
  f.doneNote:SetText(f.docked and "Done locks your commendations for this farm." or "")
end
-- a commendation for you, while the window is open: listed in it instead of a toast
function C.RecapCommended(from, kindName, bad, add, why)
  local f = recap
  if not (f and f:IsShown()) then return false end
  local line = bad and ("|cffff6a5a" .. from .. "|r: " .. (kindName or "") .. "  |cff9d9d9dno penalty|r")
    or ("|cff6ee678" .. from .. "|r: " .. (kindName or "") .. ((add and add > 0) and ("  |cff6ee678+" .. add .. " Renown|r") or ""))
  table.insert(f.gotLines, line)
  f.gotText:SetText(table.concat(f.gotLines, "\n"))
  return true
end
-- the commend window (Vouch.lua) docks inside this one when it's open
function C.RecapDock(pop)
  local f = recap
  if not (f and f:IsShown() and pop) then return false end
  pop:SetParent(f); pop:ClearAllPoints(); pop:SetPoint("TOP", f.slot, "TOP", 0, 0)
  pop:SetFrameLevel(f:GetFrameLevel() + 3)
  if pop.SetBackdropColor then pop:SetBackdropColor(0.1, 0.075, 0.045, 0.95); pop:SetBackdropBorderColor(0.55, 0.4, 0.15, 1) end
  if pop.title then pop.title:SetText("Commend your partners") end
  if pop.done then pop.done:Hide() end
  f.docked = pop
  if not pop.kinaDockHook then
    pop.kinaDockHook = true
    pop:HookScript("OnHide", function() if recap and recap.docked == pop then recap.docked = nil; relayoutRecap(recap) end end)
  end
  relayoutRecap(f)
  return true
end
-- the last scored farm's recap again
function P.ShowLastRecap()
  for _, s in ipairs(C.db.sessions or {}) do
    if s.prog and s.prog.score then return C.FarmRecap(s, s.prog.score) end
  end
  C.Print("no farm has earned Renown yet, so there's no recap to show.")
end
function C.FarmRecap(s, sc)
  local f = buildRecap()
  f.title:SetText(GOLDC .. "Farm complete|r")
  local mates = {}
  for _, who in ipairs(P.Members(s)) do
    local n = (tostring(who):match("^([^%-%s]+)")) or who
    if n ~= (UnitName and UnitName("player")) then mates[#mates + 1] = n end
  end
  f.sub:SetText((s and s.label or "Farm") .. "  ·  " .. string.format("%d h %02d m", math.floor(sc.mins / 60), sc.mins % 60)
    .. (#mates > 0 and ("  ·  with " .. table.concat(mates, ", ")) or ""))
  local quest = s and s.money and s.money.quest or 0
  local p = sc.parts
  local function pct(v) return "+" .. math.floor((v or 0) * 100 + 0.5) .. "%" end
  local money = function(c) return C.Money and C.Money(math.floor(c or 0)) or num(c) end
  local xp = s and s.gameXP or 0
  local xph = C.GameXPPerHour and C.GameXPPerHour(s)
  local ICON = { "Interface\\Icons\\INV_Misc_Coin_02", "Interface\\Icons\\Spell_Holy_SurgeOfLight", "Interface\\Icons\\INV_Misc_Note_02", "Interface\\Icons\\INV_Misc_Coin_17" }
  local rows = {
    { "Gold  |cff9d9d9dthe whole group|r", GREENC .. "+" .. money(sc.groupLoot) .. "|r  |cff9d9d9d" .. money(sc.groupLoot / math.max(sc.mins / 60, 0.25)) .. "/h|r" },
    { "Character XP", GREENC .. "+" .. num(xp) .. "|r" .. (xph and ("  |cff9d9d9d" .. num(xph) .. "/h|r") or "") },
    { GOLDC .. "Renown|r", GREENC .. "+" .. num(sc.earned) .. "|r" },
    { GREYC .. "Quest gold (not counted)|r", GREYC .. (quest > 0 and money(quest) or "-") .. "|r" },
  }
  for i, row in ipairs(f.rows) do row[1]:SetText(rows[i][1]); row[2]:SetText(rows[i][2]); row[3]:SetTexture(ICON[i]) end
  f.why:SetText(string.format("%d active min x pace %.1f, bonuses %s (party %s, streak %s, campfire %s, bond %s, tracks %s). Each commendation adds 10%%.",
    sc.mins, sc.pace, pct(sc.bonus), pct(p.party), pct(p.streak), pct(p.campfire), pct(p.bond), pct(p.tracks)))
  -- the three tracks, after this farm
  local st = P.State()
  local function setTrack(i, label, fillFrac, right, note, r, g, b)
    local t = f.tracks[i]
    t.l:SetText(label); t.r:SetText(right); t.n:SetText(note)
    local w = (t.bg:GetWidth() or 360)
    t.fill:SetWidth(math.max(1, w * math.max(0, math.min(1, fillFrac))))
    t.fill:SetColorTexture(r, g, b, 1)
  end
  local rk, cur, nx = P.Rank(st.renown)
  setTrack(1, "Renown  |cff9d9d9d· the ring|r", nx and ((st.renown - cur.at) / math.max(1, nx.at - cur.at)) or 1,
    num(st.renown) .. (nx and (" / " .. num(nx.at)) or ""), (P.QCOLOR[cur.q] or "") .. cur.title .. "|r" .. (nx and ("  |cff9d9d9d· next: " .. nx.title .. "|r") or ""), 0.3, 0.52, 0.9)
  local bT, hT
  for _, tr in ipairs(S().tracks) do if tr.id == "banner" then bT = tr.tiers elseif tr.id == "hoard" then hT = tr.tiers end end
  local function gold(g) return money((g or 0) * 10000) end
  local function ladder(v, tiers) local lv = tierOf(v or 0, tiers or {}); return lv, (tiers or {})[lv + 1], (tiers or {})[lv] or 0 end
  local gph = P.BestGph()
  local bl, bn, bp = ladder(gph, bT)
  local newBest = (sc.groupGph or 0) > (sc.bannerBefore or 0) + 0.005
  setTrack(2, "Best gold / hour  |cff9d9d9d· the banner|r", bn and ((gph - bp) / math.max(0.001, bn - bp)) or 1,
    gold(gph) .. (bn and (" / " .. gold(bn)) or ""), newBest and ("|cff6ee678New best: " .. gold(sc.groupGph) .. " an hour!|r") or ("|cff9d9d9dthis farm " .. gold(sc.groupGph or 0) .. " an hour · banner " .. bl .. "|r"), 0.85, 0.6, 0.18)
  local hl, hn, hp = ladder(st.gold, hT)
  setTrack(3, "Gold farmed  |cff9d9d9d· the coin hoard|r", hn and ((st.gold - hp) / math.max(0.001, hn - hp)) or 1,
    gold(st.gold) .. (hn and (" / " .. gold(hn)) or ""), "|cff6ee678+" .. gold(sc.groupLoot / 10000) .. "|r  |cff9d9d9d· hoard " .. hl .. "|r", 0.85, 0.6, 0.18)
  local up = {}
  if sc.rankUp then local t = S().ranks[sc.rankUp]; up[#up + 1] = "NEW RANK: " .. (P.QCOLOR[t.q] or "") .. t.title .. "|r" end
  f.banner:SetText(#up > 0 and ("|cffffe090" .. table.concat(up, "   ") .. "|r") or "")
  f.gotLines = {}
  f.gotText:SetText("|cff9d9d9dNone yet. They appear here as they arrive.|r")
  relayoutRecap(f)
  f:Show(); if f.Raise then f:Raise() end
  if sc.rankUp and C.PlayCue then C.PlayCue("level") end
  C.Print(string.format("farm complete: +%s Renown (%d min, pace x%.1f, bonus +%d%%).", num(sc.earned), sc.mins, sc.pace, math.floor(sc.bonus * 100 + 0.5)))
end

-- 1.1.0 (Taylor: no debts): once, clear anything still queued about debts. Splits stay in
-- the farm logs as information; nobody owes anybody.
if C.On then C.On("PLAYER_LOGIN", function()
  local d = C.db
  if not d or d.debtsRetired then return end
  d.debtsRetired = C.Now and C.Now() or 0
  if d.forgive then d.forgive.pending = {}; d.forgive.asks = {} end
  if d.share then d.share.courier = {} end
end) end

-- 2.0 (Taylor: "it reset all of us back to level 1"): the Kina level you earned before 2.0
-- carries into Season 1. Once per profile: your season XP starts at the start of the level
-- you had (Kina level I to XX maps to 1 to 20). Never lowers anything.
function P.CarryOldLevel()
  local d = C.db
  if not d or d.levelCarried or not (C.Rep and C.Rep.Mine) then return end
  local ok, m = pcall(C.Rep.Mine)
  if not ok or type(m) ~= "table" or not m.ok then return end
  d.levelCarried = C.Now and C.Now() or 0
  local lv = math.max(1, math.min(#S().levels, tonumber(m.level) or 1))
  local st = P.State()
  local at = S().levels[lv] or 0
  if (st.xp or 0) < at then st.xp = at end
  if lv > 1 then C.Print(string.format("|cffffc54aKina 2.0:|r your Kina level %d carries into Season 1.", lv)) end
end
-- 2.0.6: once per profile, every 2.0 farm that never got its Kina XP and Renown (the
-- network wasn't reaching anyone, or a crash said "solo") is scored again under the rules
-- above and paid, with any commendations waiting for it. A farm that already earned is
-- never paid twice (it has a score). 2.0 farms are the ones with season activity (prog).
-- 2.0.15b (Taylor: "The banner didn't update from my past farms"): the banner's best gold
-- per hour is worked out once from every farm this season already scored
function P.BackfillBanner()
  local d = C.db
  if not d or d.bannerFilled then return end
  local st = P.State()
  local since = st.started or 0
  local best = st.best.groupGph or 0
  for _, s in ipairs(d.sessions or {}) do
    local sc = type(s.prog) == "table" and s.prog.score
    if type(sc) == "table" and sc.groupLoot and sc.mins and sc.mins >= 15 and (s.start or 0) >= since then
      best = math.max(best, (sc.groupLoot / 10000) / math.max(sc.mins / 60, 0.25))
    end
  end
  st.best.groupGph = best
  d.bannerFilled = true
end
function P.Rescore()
  if C.realmPending then
    if C.After then C.After(5, function() pcall(P.Rescore) end) end
    return 0
  end
  local d = C.db
  if not d or d.rescored206 then return 0 end
  d.rescored206 = C.Now and C.Now() or 0
  local n, total = 0, 0
  for _, s in ipairs(d.sessions or {}) do
    if s ~= C.session and type(s.prog) == "table" and not s.prog.score and (s.prog.act or 0) >= 1 then
      s.progCredited, s.progWhy, s.rescore = nil, nil, true
      local ok, sc = pcall(P.Credit, s, true)
      if ok and sc then n = n + 1; total = total + (sc.earned or 0) end
      s.rescore = nil
    end
  end
  if n > 0 and C.Print then
    C.Print(string.format("|cffffc54aKina 2.0.6:|r %d past farm%s scored again: +%d Renown that was missed.", n, n == 1 and "" or "s", total))
  end
  return n, total
end
if C.On then C.On("PLAYER_LOGIN", function()
  local function go() pcall(P.CarryOldLevel); pcall(P.Rescore); pcall(P.BackfillBanner); pcall(P.HistBackfill) end
  if C.After then C.After(3, go) else go() end
end) end
