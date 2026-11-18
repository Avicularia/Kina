-- Kina: AH prices from every Kina on the realm (1.0.7, Taylor). Over the Kina network
-- (Net.lua), not only the guild or group:
--  * after your AH scan, your Kina posts one short line: "I have prices from <time>"
--  * a Kina whose prices are older asks one Kina with newer ones, and gets the scan as
--    invisible addon messages (only prices: no gold, no debts, no loot)
--  * a price from the network only counts when several Kinas agree on it: at least two
--    different players, within 35% of each other, weighted by their standing (a negative
--    standing counts for nothing, Unproven for half). One made-up scan can't move a price.
--  * your own scan and your guild's still count as before; the 3x check against your own
--    scan still applies; the freshest agreed price wins
-- Messages (prefix KinaNet): PS|time|count|standing (channel), PQ|time (to one),
--   PZB|time|parts|standing, PZ|time|packed items, PZE|time|parts (in the Kina room)
local _, C = ...
local NP = {}
C.NetPrices = NP
NP.MAX_AGE = 3 * 86400      -- network scans older than this aren't used
NP.MAX_SOURCES = 8          -- the newest few players' scans are kept
NP.AGREE = 0.35             -- within 35% of the middle price
NP.NEED_WEIGHT = 2          -- two Vouched players (or four Unproven) must agree
NP.ASK_EVERY = 20 * 60      -- ask someone for prices at most this often
NP.ANSWER_MAX = 3           -- answer at most this many askers...
NP.ANSWER_WINDOW = 10 * 60  -- ...per 10 minutes
NP.NEWER_BY = 10 * 60       -- only ask for a scan at least this much newer than what you have

local function b36(n) return C.Share and C.Share._b36 and C.Share._b36(n) or tostring(n) end
local function n36(s, max) return C.Share and C.Share._n36 and C.Share._n36(s, max) or tonumber(s) end
local function Net() return C.Net end
function NP.Enabled() return not (C.settings and C.settings.netPricesOff) and Net() and Net().Enabled() end
local function store()
  C.db.netPrices = type(C.db.netPrices) == "table" and C.db.netPrices or {}
  return C.db.netPrices
end
local WEIGHT = { Delinquent = 0, Disgraced = 0, Oathbreaker = 0, Blacklisted = 0, Unproven = 0.5 }
function NP.Weight(standing)
  if not standing or standing == "" then return 0.5 end
  local w = WEIGHT[standing]
  if w == nil then return 1 end
  return w
end

------------------------------------------------------------------ announcing your scan
local function myStanding()
  local m = C.Rep and C.Rep.Mine and C.Rep.Mine()
  return m and m.standing or "Unproven"
end
function NP.Announce()
  if not NP.Enabled() then return end
  local m = C.market
  if not (m and m.scanTime and m.items) then return end
  if C.Now() - m.scanTime > NP.MAX_AGE then return end
  local n = 0
  for _, mi in pairs(m.items) do if mi.m and mi.m > 0 then n = n + 1 end end
  if n == 0 then return end
  Net().Broadcast(string.format("PS|%s|%s|%s", b36(m.scanTime), b36(n), myStanding()))
end
if C.OnMarket then C.OnMarket(function() if C.After then C.After(5, NP.Announce) end end) end
C.On("PLAYER_LOGIN", function() if C.After then C.After(40, NP.Announce) end end)

------------------------------------------------------------------ asking
-- the newest prices you already have (your scan, your guild's, or the network's)
function NP.NewestHave()
  local t = (C.market and C.market.scanTime) or 0
  if C.Share and C.Share.NewestScan then local g = C.Share.NewestScan(); if g and g > t then t = g end end
  for _, s in pairs(store()) do if (s.t or 0) > t then t = s.t end end
  return t
end
local asks = {}       -- when we asked, this window (up to 3 different players)
local function onScanOffer(from, f)
  if not NP.Enabled() then return end
  local t, n, st = n36(f[2]), n36(f[3], 100000), f[4]
  if not (t and n and n > 0) then return end
  if C.Now() - t > NP.MAX_AGE or t > C.Now() + 3600 then return end
  if NP.Weight(st) <= 0 then return end -- a negative standing: not worth asking
  -- newer than your own scan (agreement needs a few players, so other network scans
  -- don't stop it), and not someone already asked
  local own = math.max((C.market and C.market.scanTime) or 0, (C.Share and C.Share.NewestScan and C.Share.NewestScan()) or 0)
  if t < own + NP.NEWER_BY then return end
  local have = store()[from:lower()]
  if have and (have.t or 0) >= t then return end
  local now = C.Now()
  for i = #asks, 1, -1 do if now - asks[i] > NP.ASK_EVERY then table.remove(asks, i) end end
  if #asks >= 3 then return end
  asks[#asks + 1] = now
  Net().Tell(from, "PQ|" .. b36(t))
end
NP._offer = onScanOffer

------------------------------------------------------------------ packing a scan small
-- 1.0.7 (Taylor: "much smaller packages"): about 4 letters an item instead of ~15.
--  * 92 safe letters (printable, no "|" or "\\")
--  * items in number order; each item is the gap from the one before (1 letter; letter 0
--    then 3 letters is a jump to an exact number)
--  * the price as a step on a scale accurate to 0.3% (2 letters), the number listed
--    roughly (1 letter)
-- Every message starts fresh, so a lost message only loses its own ~60 items.
local ALPHA = {}
for c = 33, 126 do if c ~= 124 and c ~= 92 then ALPHA[#ALPHA + 1] = string.char(c) end end
local B = #ALPHA -- 92
local VAL = {}
for i, ch in ipairs(ALPHA) do VAL[ch] = i - 1 end
local LNMAX = math.log(1e11)        -- prices up to 10 million gold
local PSTEPS = B * B - 1
local QMAX = math.log(100000)
NP.Codec = {}
local function enc(n, width)
  local t = {}
  for i = width, 1, -1 do local d = n % B; t[i] = ALPHA[d + 1]; n = (n - d) / B end
  return table.concat(t)
end
local function dec(s, pos, width)
  local n = 0
  for i = pos, pos + width - 1 do
    local v = VAL[s:sub(i, i)]
    if not v then return nil end
    n = n * B + v
  end
  return n
end
function NP.Codec.Price(p)
  if p < 1 then p = 1 end
  return math.min(PSTEPS, math.floor(math.log(p) / LNMAX * PSTEPS + 0.5))
end
function NP.Codec.UnPrice(c) return math.floor(math.exp(c / PSTEPS * LNMAX) + 0.5) end
function NP.Codec.Qty(q)
  if not q or q <= 0 then return 0 end
  return math.min(B - 1, 1 + math.floor(math.log(q) / QMAX * (B - 2) + 0.5))
end
function NP.Codec.UnQty(c) if c == 0 then return 0 end; return math.floor(math.exp((c - 1) / (B - 2) * QMAX) + 0.5) end
-- rows: sorted { {id, price, qty} } -> list of payload strings (each <= maxLen)
function NP.Codec.Pack(rows, maxLen)
  local out, cur, prev = {}, {}, nil
  local len = 0
  for _, r in ipairs(rows) do
    local gap = prev and (r[1] - prev) or nil
    local head
    if gap and gap >= 1 and gap < B then head = ALPHA[gap + 1] else head = ALPHA[1] .. enc(r[1], 3) end
    local piece = head .. enc(NP.Codec.Price(r[2]), 2) .. ALPHA[NP.Codec.Qty(r[3]) + 1]
    if len + #piece > maxLen then
      out[#out + 1] = table.concat(cur); cur, len = {}, 0
      head = ALPHA[1] .. enc(r[1], 3) -- every message starts fresh
      piece = head .. enc(NP.Codec.Price(r[2]), 2) .. ALPHA[NP.Codec.Qty(r[3]) + 1]
    end
    cur[#cur + 1] = piece; len = len + #piece; prev = r[1]
  end
  if #cur > 0 then out[#out + 1] = table.concat(cur) end
  return out
end
function NP.Codec.Unpack(s, into)
  local pos, prev, n = 1, nil, 0
  while pos <= #s do
    local g = VAL[s:sub(pos, pos)]
    if g == nil then return n end
    local id
    if g == 0 then id = dec(s, pos + 1, 3); pos = pos + 4
    else if not prev then return n end; id = prev + g; pos = pos + 1 end
    local pc, qc = dec(s, pos, 2), dec(s, pos + 2, 1)
    if not (id and pc and qc) then return n end
    pos = pos + 3
    local price = NP.Codec.UnPrice(pc)
    into[id] = { m = price, d = price, q = NP.Codec.UnQty(qc) }
    prev = id; n = n + 1
  end
  return n
end

------------------------------------------------------------------ sending: once, to everyone
-- An ask makes the holder send its scan once in the Kina room (not to each asker): every
-- Kina that wants newer prices takes it from the same messages. At most once per 30
-- minutes per scan. Items that sell go first, then the rest of the scan.
NP.RESEND_GAP = 30 * 60
local lastSent = { t = 0, at = 0 }
local MAXP = 255 - 20
function NP.SendScan()
  local m = C.market
  if not (NP.Enabled() and m and m.scanTime and m.items) then return false end
  if lastSent.t == m.scanTime and C.Now() - lastSent.at < NP.RESEND_GAP then return false end
  lastSent.t, lastSent.at = m.scanTime, C.Now()
  local vel = m.vel or {}
  local selling, rest = {}, {}
  for id, mi in pairs(m.items) do
    if mi.m and mi.m > 0 then
      local row = { id, mi.m, mi.q or 0 }
      if vel[id] and (vel[id].v or 0) > 0 then selling[#selling + 1] = row else rest[#rest + 1] = row end
    end
  end
  local function byId(a, b) return a[1] < b[1] end
  table.sort(selling, byId); table.sort(rest, byId)
  local parts = NP.Codec.Pack(selling, MAXP)
  for _, p in ipairs(NP.Codec.Pack(rest, MAXP)) do parts[#parts + 1] = p end
  local tt = b36(m.scanTime)
  Net().Broadcast(string.format("PZB|%s|%s|%s", tt, b36(#parts), myStanding()))
  for k, p in ipairs(parts) do Net().BroadcastBulk("PZ|" .. tt .. "|" .. p) end
  Net().BroadcastBulk("PZE|" .. tt .. "|" .. b36(#parts))
  if C.NetNote then pcall(C.NetNote, string.format("sent your AH scan to every Kina: %d items in %d messages (about %d s)", #selling + #rest, #parts + 2, #parts + 2)) end
  return true
end
local answered = {}
local function onAsk(from, f)
  if not NP.Enabled() then return end
  local m = C.market
  local t = n36(f[2])
  if not (m and m.scanTime and t == m.scanTime) then return end
  local now = C.Now()
  for i = #answered, 1, -1 do if now - answered[i] >= NP.ANSWER_WINDOW then table.remove(answered, i) end end
  if #answered >= NP.ANSWER_MAX then return end
  answered[#answered + 1] = now
  NP.SendScan()
end

------------------------------------------------------------------ receiving (anyone listening)
local incoming = {}
local function wantsFrom(from, t)
  if not NP.Enabled() then return false end
  if C.Now() - t > NP.MAX_AGE or t > C.Now() + 3600 then return false end
  local own = math.max((C.market and C.market.scanTime) or 0, (C.Share and C.Share.NewestScan and C.Share.NewestScan()) or 0)
  if t < own + NP.NEWER_BY then return false end
  local have = store()[from:lower()]
  return not (have and (have.t or 0) >= t)
end
local function onBegin(from, f)
  local t, n, st = n36(f[2]), n36(f[3], 5000), f[4]
  if not (t and n) or NP.Weight(st) <= 0 or not wantsFrom(from, t) then return end
  incoming[from:lower()] = { t = t, st = st, rows = {}, parts = 0, want = n }
end
local function onPart(from, f, raw)
  local p = incoming[from:lower()]
  local t = n36(f[2])
  if not (p and t == p.t) then return end
  -- the payload is everything after the second "|" (its letters never include "|")
  local payload = raw:match("^PZ|[^|]*|(.*)$") or ""
  NP.Codec.Unpack(payload, p.rows)
  p.parts = p.parts + 1
end
local function onFinish(from, f)
  local key = from:lower()
  local p = incoming[key]
  local t = n36(f[2])
  if not (p and t == p.t) then return end
  incoming[key] = nil
  local count = 0
  for _ in pairs(p.rows) do count = count + 1 end
  if count == 0 then return end
  local s = store()
  s[key] = { name = from, t = p.t, st = p.st, items = p.rows, got = C.Now(), mkey = C.MarketKey and C.MarketKey() }
  local list = {}
  for k, v in pairs(s) do list[#list + 1] = { k = k, t = v.t or 0 } end
  table.sort(list, function(a, b) return a.t > b.t end)
  for i = NP.MAX_SOURCES + 1, #list do s[list[i].k] = nil end
  NP.Invalidate()
  if C.Share and C.Share.InvalidateMarket then C.Share.InvalidateMarket() end
  if C.NetNote then pcall(C.NetNote, string.format("got an AH scan from %s on the Kina network: %d items", from, count)) end
  C.Print(string.format("got AH prices from the Kina network (%d items from %s). They count where several Kinas agree.", count, from))
end

------------------------------------------------------------------ agreeing
-- One snapshot built from every network scan: per item, the middle price of the scans,
-- kept only where scans from at least two players (weighted by standing) agree within 35%.
local cons
function NP.Invalidate() cons = nil end
function NP.Snapshot()
  if not NP.Enabled() then return nil end
  if cons ~= nil then return cons or nil end
  local now, mk = C.Now(), C.MarketKey and C.MarketKey()
  local by = {}
  local newest = 0
  for _, s in pairs(store()) do
    if s.items and now - (s.t or 0) < NP.MAX_AGE and (not mk or not s.mkey or s.mkey == mk) then
      local w = NP.Weight(s.st)
      if w > 0 then
        for id, mi in pairs(s.items) do
          by[id] = by[id] or {}
          table.insert(by[id], { m = mi.m, row = mi, w = w, t = s.t, who = s.name })
        end
      end
    end
  end
  local items = {}
  local count = 0
  for id, list in pairs(by) do
    if #list >= 2 then
      table.sort(list, function(a, b) return a.m < b.m end)
      local mid = list[math.ceil(#list / 2)].m
      local agree, w, who, best = {}, 0, {}, nil
      for _, e in ipairs(list) do
        if math.abs(e.m - mid) <= mid * NP.AGREE then
          agree[#agree + 1] = e; who[e.who or "?"] = true
          w = w + e.w
          if not best or e.t > best.t then best = e end
        end
      end
      local people = 0
      for _ in pairs(who) do people = people + 1 end
      if people >= 2 and w >= NP.NEED_WEIGHT then
        local m = agree[math.ceil(#agree / 2)].m
        items[id] = { m = m, d = best.row.d or m, q = best.row.q or 0, n = best.row.n or 0, net = people }
        if best.t > newest then newest = best.t end
        count = count + 1
      end
    end
  end
  if count == 0 then cons = false; return nil end
  cons = { t = newest, items = items, name = "the Kina network", net = true }
  return cons
end

------------------------------------------------------------------ start
if C.After then
  C.After(0, function()
    local N = Net()
    if not N then return end
    N.On("PS", onScanOffer)
    N.On("PQ", onAsk)
    N.On("PZB", onBegin)
    N.On("PZ", onPart)
    N.On("PZE", onFinish)
  end)
end
