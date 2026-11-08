-- Kina: checks the saved data when it loads. A saved file can be damaged (a crash
-- while saving, an old version, or someone editing it). Anything with the wrong shape
-- is dropped here, so Kina never errors on it. Missing parts are then filled in fresh
-- (Core.lua). Edited event logs still load; they just fail their chain check (Log.lua),
-- which is how edits show.
local _, C = ...

local N, S, B, T = "number", "string", "boolean", "table"
-- spec: a type name, a set of type names, or { t = T, f = {fields}, each = spec, req = {required fields} }
local function ok(v, spec)
  if type(spec) == "string" then return type(v) == spec end
  if spec.t == nil then return spec[type(v)] == true end -- a set of types
  return type(v) == spec.t
end

local clean
-- 1.0.10: what was dropped, by path ("sessions.3.sync.chain.12.data"), so the
-- "saved data was cleaned up" note can be traced to its cause
local dropped
local function note(path, k) if dropped and #dropped < 20 then dropped[#dropped + 1] = (path or "") .. "." .. tostring(k) end end
local function cleanTable(t, spec, path)
  if spec.f then
    for k, sub in pairs(spec.f) do
      local v = t[k]
      if v ~= nil then
        if not ok(v, sub) then note(path, k .. "(" .. type(v) .. ")"); t[k] = nil
        elseif type(sub) == "table" and sub.t == T then
          clean(v, sub, (path or "") .. "." .. tostring(k))
          for _, r in ipairs(sub.req or {}) do if v[r] == nil then note(path, k .. " missing " .. r); t[k] = nil; break end end
        end
      end
    end
  end
  if spec.each then
    local list = spec.list
    local keep = {}
    for k, v in pairs(t) do
      if spec.f and spec.f[k] then -- a named field, already checked
      elseif ok(v, spec.each) and (function()
          -- clean the entry first: a required field of the wrong type is removed there
          if type(spec.each) == "table" and spec.each.t == T then clean(v, spec.each, (path or "") .. "." .. tostring(k)) end
          for _, r in ipairs(type(spec.each) == "table" and spec.each.req or {}) do if v[r] == nil then note(path, tostring(k) .. " missing " .. r); return false end end
          return true end)() then
        if list and type(k) == "number" then keep[#keep + 1] = { k, v } end
      elseif list and type(k) == "number" then note(path, tostring(k) .. "(" .. type(v) .. ")") -- dropped from the list
      else note(path, tostring(k) .. "(" .. type(v) .. ")"); t[k] = nil end
    end
    if list then
      -- lists are rebuilt in order without the bad entries
      table.sort(keep, function(a, b) return a[1] < b[1] end)
      for k in pairs(t) do if type(k) == "number" then t[k] = nil end end
      for i, kv in ipairs(keep) do t[i] = kv[2] end
    end
  end
end
clean = function(t, spec, path) if type(t) == T and type(spec) == T and spec.t == T then cleanTable(t, spec, path) end end

local NUMS = { N = true }
local function map(each) return { t = T, each = each } end
local function list(each) return { t = T, each = each, list = true } end
local NUMMAP = map(N)

local transfer = { t = T, f = { from = S, to = S, amt = N }, req = { "from", "to", "amt" } }
local split = { t = T, f = { total = N, each = N, transfers = list(transfer), paid = map({ number = true, boolean = true }),
  received = map({ number = true, boolean = true }), incomes = NUMMAP, forgiven = NUMMAP, ext = NUMMAP, plea = map(B), pleaFrom = map(B), lapsed = map(B), offered = NUMMAP, refusedSeen = NUMMAP, clock = NUMMAP, pclock = NUMMAP, clockAt = NUMMAP } }
local chainEv = { t = T, f = { seq = N, origin = S, oseq = N, kind = S, t = N, hash = S, data = S }, req = { "seq", "origin", "kind", "hash" } }
local sync = { t = T, f = { sid = S, leader = S, head = N, hash = S, oseq = N, closed = B, chain = map(chainEv),
  outbox = map({ t = T, f = { kind = S, data = S, t = N, at = N } }), seenOrig = NUMMAP, buf = map(T), pauses = list({ t = T, f = { from = N, to = N } }) },
  req = { "sid" } }
local session = { t = T, f = { start = N, stop = N, last = N, label = S, kills = N, money = NUMMAP, items = NUMMAP, byNpc = NUMMAP,
  party = list({ t = T, f = { name = S } }), split = split, sync = sync, log = list(T), g = T, posted = NUMMAP, startCounts = NUMMAP,
  paused = B, pauseAt = N, pausedSecs = N, gameXP = N, char = S, class = S, lastKill = N, idleFixed = B,
  hold = { t = T, f = { at = N, me = S, peers = map(S), done = B, ready = N, leader = S } }, endGold = N, endItems = N, endUsed = N, endWorth = N, startMoney = N, limit = N,
  result = { t = T, f = { secs = N, cash = N, items = N, used = N, total = N, perHour = N, coin = N, pickpocket = N, vendor = N,
    spent = N, kills = N, net = B, income = B } },
  gview = { t = T, f = { secs = N, net = N, coin = N, items = N, used = N, kills = N, paused = B } }, why = S, zone = S, skins = N, nodes = N,
  skinItems = NUMMAP, gather = NUMMAP, excl = { t = T, f = { coin = N, items = NUMMAP } }, sx = map(NUMMAP), byParty = B, camp = S, startBag = N,
  minLvl = N, maxLvl = N, groupN = N, noSplit = B, apartTicks = N, togetherTicks = N, apartAsked = B },
  req = { "start" } }
local SETTINGS = {}
for _, k in ipairs({ "ahCut", "depositFloor", "vendorMargin", "killsPerHour", "launchTime", "minDealProfit", "farmPreset", "widgetAlpha",
  "picksPerHour", "textScale", "minROI", "bagSlots", "deFriend", "deSkill", "farmHi", "farmLo", "investDays", "investScans", "maxWaitDays",
  "minConfidence", "minProfit", "minimapAngle", "partnerLevel", "postDuration", "priorKills", "rareRate", "tripMinutes", "widgetScale",
  "kinaScale", "dataNoticeSeen", "welcomed", "lastKinaLv" }) do SETTINGS[k] = N end
for _, k in ipairs({ "hudShown", "autoScan", "farmSound", "tooltip", "worthOnly", "assumeSkinning", "autoOpen", "deMine", "hotAlerts",
  "matLowest", "farmNoSplit", "text115", "minimapHide", "plateKills", "shareData", "shareEnchanters", "showEnemy", "showUnique", "dockAH", "craftMine", "groupAd", "leaveCloth", "deTip", "themeMusic" }) do SETTINGS[k] = B end
for _, k in ipairs({ "pos", "farmAutoJoin", "hotHide", "partnerProfs", "partnerSlots", "lowLevelSeen", "forgiven" }) do SETTINGS[k] = T end
SETTINGS.partnerClass = S
SETTINGS.look = S
SETTINGS.autoLootWas = S
SETTINGS.themeMutedMusic = B
SETTINGS.kinaVolume = N
SETTINGS.tipOnly = B
SETTINGS.askScan = B
SETTINGS.rulesFell = N
SETTINGS.rulesBlack = B
SETTINGS.rulesWarn5 = N
SETTINGS.rulesWarn10 = N
SETTINGS.decayFrom = N
SETTINGS.decayWeeks = N
SETTINGS.tipDE = B
SETTINGS.lastStanding = S
SETTINGS.tourSeen = S
SETTINGS.tourRewarded = B
SETTINGS.updCheck = T
SETTINGS.tourOff = B

local DB = { t = T, f = {
  settings = { t = T, f = SETTINGS },
  markets = map({ t = T, f = { items = map(T), history = map(T), scanTime = N } }),
  items = map({ t = T, f = { name = S, q = N, il = N, rl = N, cls = N, sub = N, eq = S, vend = N, bind = N } }),
  vendor = map({ t = T, f = { p = N, t = N, c = N } }), noDE = NUMMAP, loot = map({ t = T, f = { kills = N, looted = N, coin = N, coinLoots = N, pp = N, ppCoin = N, skins = N,
    items = NUMMAP, ppItems = NUMMAP, skinItems = NUMMAP } }),
  nodes = map({ t = T, f = { n = N, items = NUMMAP } }),
  sessions = list(session), activeSession = session,
  stock = map(T), chars = map({ t = T, f = { prof = NUMMAP, bank = NUMMAP, known = T, level = N } }),
  log = { t = T, f = { lines = list({ t = T, f = { e = S, h = S }, req = { "e", "h" } }), base = S, summary = NUMMAP,
    repState = { t = T, f = { xp = N, share = B, cap = NUMMAP, rep = N, noProg = map(B), lastRefused = N,
      maxEver = N, lowEver = N, recoverTo = N, black = B, everBlack = B, jailUsed = B, frozen = B, negSecs = N, posSecs = N, lastT = N,
      fell = N, lastFall = N, lastFarmT = N, badTimes = list(N), badSeen = N, tourDone = B } }, repHash = S } },
  mark = { t = T, f = { rep = N, black = B, t = N } },
  settles = list({ t = T, f = { t = N, who = S, gave = N, got = N, via = S, paidOff = N, cameIn = N, conf = N,
    covers = list({ t = T, f = { start = N, label = S, amt = N, dir = S, topup = B, total = N, stop = N, late = B }, req = { "amt", "dir" } }) },
    req = { "t", "who", "gave", "got", "via" } }),
  payout = { t = T, f = { floors = list({ t = T, f = { id = N, n = N, v = N, members = N, partners = list(S), label = S, t = N },
    req = { "id", "n", "v", "members", "partners" } }), owed = NUMMAP } },
  seenMail = NUMMAP, errlog = list(T), blocked = list(T),
  share = { t = T, f = { opts = T, authors = map(T), uid = S, notable = map(T) } },
  ledger = { t = T, f = { seen = T, seenN = NUMMAP, entries = list(T), transfers = T } },
  pockets = T, recipes = map(T), boxes = T, deObs = map({ t = T, f = { n = N, mats = NUMMAP } }), offers = T,
  lastReplicate = N, lastSnapshotSeen = N,
  mentor = { t = T, f = { eligible = B, born = N, named = S, target = S, qualified = N, done = N, asked = N, recruits = map({ t = T, f = { name = S, t = N } }) } },
  vouch = { t = T, f = { given = list({ t = T, f = { who = S, kind = N, t = N, ref = S } }), got = list({ t = T, f = { who = S, kind = N, t = N, ref = S, rep = N } }), closed = NUMMAP } },
  selftest = T, repairs = list(T), forgive = { t = T, f = { pending = list({ t = T, f = { who = S, amt = N, ref = S, t = N, kind = S }, req = { "who", "ref" } }) } },
  tradeStats = { t = T, f = { complete = N, missed = N, cancelled = N, lastMissed = N, msgs = list(S) } },
} }

-- returns how many things were dropped (for the chat note)
function C.Sanitize(db)
  if type(db) ~= T then return 0 end
  local before = 0
  local function count(t, seen)
    seen = seen or {}
    if seen[t] then return end
    seen[t] = true
    for _, v in pairs(t) do before = before + 1; if type(v) == T then count(v, seen) end end
  end
  count(db)
  dropped = {}
  local ok2, err = pcall(clean, db, DB, "")
  C.repairPaths = dropped
  dropped = nil
  local after = 0
  before, after = before, (function() local n = 0; local seen = {}
    local function c(t) if seen[t] then return end; seen[t] = true; for _, v in pairs(t) do n = n + 1; if type(v) == T then c(v) end end end
    c(db); return n end)()
  if not ok2 then return -1, err end
  return before - after
end
