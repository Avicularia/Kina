-- Kina: auction house reader.
-- Requests a full scan by itself when the auction house opens (one try per visit,
-- only after the 15-minute limit; /kina autoscan turns it off). Whenever ANY addon
-- pulls a full snapshot, Kina also reads the same rows.
local _, C = ...
local AH = C_AuctionHouse
local CHUNK = 600
local HISTORY_DAYS = 30
C.ahOpen = false
local reading, ownRequest = false, false
-- what the scan is doing right now, for the progress bar:
-- phase = idle | request | read | items | done | noreply | stopped; done/total = progress
C.scan = { phase = "idle" }
local function phase(p, done, total) local sc = C.scan; sc.phase = p; sc.done = done or 0; sc.total = total or 0; sc.t = GetTime and GetTime() or 0 end
C.ScanPhase = phase
local listeners = {}
function C.OnMarket(fn) table.insert(listeners, fn) end

local function day(t) return math.floor(t / 86400) end

-- depth price: average unit price of the cheapest `want` units on the book
local function depthPrice(ladder, want)
  local got, cost = 0, 0
  for _, step in ipairs(ladder) do
    local take = math.min(step[2], want - got)
    cost = cost + take * step[1]; got = got + take
    if got >= want then break end
  end
  if got == 0 then return nil end
  return math.floor(cost / got + 0.5)
end
C.DepthPrice = depthPrice

-- Sell-through: listings at or under the previous scan's median that are gone in
-- this one were (mostly) bought. Units per hour, smoothed over scans.
local function units(ladder, upTo)
  local n = 0
  for _, s in ipairs(ladder or {}) do if s[1] <= upTo then n = n + s[2] end end
  return n
end
local function velocity(m, items, now)
  local prevT = m.scanTime
  if not prevT then return end
  local hours = (now - prevT) / 3600
  if hours < 0.2 or hours > 30 then return end
  m.vel = m.vel or {}
  for id, prev in pairs(m.items or {}) do
    local x = prev.md or prev.m
    -- only listings at a real price count as sales: a bot buying its partner's
    -- 2000g listing is a gold transfer, not demand
    if x and prev.l and prev.l[1] then x = math.min(x, prev.l[math.min(3, #prev.l)][1] * 10) end
    if x and prev.l then
      local before = units(prev.l, x)
      local after = items[id] and units(items[id].l, x) or 0
      local obs = math.max(0, before - after) / hours
      local v = m.vel[id]
      if v then v.v = v.v * 0.7 + obs * 0.3; v.n = math.min(50, v.n + 1); v.t = now
      else m.vel[id] = { v = obs, n = 1, t = now } end
    end
  end
  for id, v in pairs(m.vel) do if now - (v.t or 0) > 14 * 86400 then m.vel[id] = nil end end
end

local function commit(acc, rows)
  local m = C.market
  -- a scan read without a reply of our own is only as new as the last snapshot event seen
  local now = C.stampOverride or C.Now()
  C.stampOverride = nil
  local today = day(now)
  local items, ids = {}, {}
  for id, a in pairs(acc) do
    -- cheapest of ANY suffix: what a disenchanter pays
    local anyMin
    for unit in pairs(a.lv) do if not anyMin or unit < anyMin then anyMin = unit end end
    for unit in pairs(a.sx) do if not anyMin or unit < anyMin then anyMin = unit end end
    local sxLadder = {}
    for unit, st in pairs(a.sx) do sxLadder[#sxLadder + 1] = { unit, st[1], st[2], st[3] } end
    table.sort(sxLadder, function(x, y) return x[1] < y[1] end)
    for i = 9, #sxLadder do sxLadder[i] = nil end
    if not next(a.lv) then -- only suffixed versions listed: no plain price, but keep the DE view
      items[id] = { q = 0, n = 0, l = {}, any = anyMin, sxq = a.sxq, sl = sxLadder, sxn = a.sxn }
      ids[#ids + 1] = id
    else
    local ladder = {}
    for unit, st in pairs(a.lv) do ladder[#ladder + 1] = { unit, st[1], st[2] } end
    table.sort(ladder, function(x, y) return x[1] < y[1] end)
    local keep = {}
    for i = 1, math.min(8, #ladder) do keep[i] = ladder[i] end
    local med
    do -- quantity-weighted median of the whole book
      local half, run = a.qty / 2, 0
      for _, s in ipairs(ladder) do run = run + s[2]; if run >= half then med = s[1]; break end end
    end
    items[id] = { m = ladder[1] and ladder[1][1], d = depthPrice(ladder, 20), md = med,
      q = a.qty, n = a.rows, l = keep, any = anyMin, sxq = a.sxq, sl = (#sxLadder > 0) and sxLadder or nil, sxn = a.sxn }
    ids[#ids + 1] = id
    if a.quality and a.quality >= 0 then
      local r = C.db.items[id] or {}
      if r.q == nil then r.q = a.quality; C.db.items[id] = r end
    end
    -- daily history (one point per day, latest scan of the day wins)
    local h = m.history[id]
    if not h then h = {}; m.history[id] = h end
    h[today] = { items[id].m, med, a.qty }
    for d in pairs(h) do if d < today - HISTORY_DAYS then h[d] = nil end end
    end
  end
  velocity(m, items, now)
  -- how many scans have seen each item (Investments need history)
  m.seen = m.seen or {}
  for id in pairs(items) do m.seen[id] = (m.seen[id] or 0) + 1 end
  -- last 10 scan prices per item (going rate = median of the book), for volatility
  m.ticks = m.ticks or {}
  for id, it in pairs(items) do
    local p = it.md or it.m
    if p and p > 0 then
      local t = m.ticks[id]
      if not t then t = {}; m.ticks[id] = t end
      local last = t[#t]
      if last and now - last[1] < 600 then t[#t] = { now, p } else t[#t + 1] = { now, p } end
      while #t > 10 do table.remove(t, 1) end
    end
  end
  for id, t in pairs(m.ticks) do if not items[id] and t[#t] and now - t[#t][1] > 7 * 86400 then m.ticks[id] = nil end end
  m.items = items
  m.scanTime = now
  m.family = C.VersionFamily()
  m.rows = rows
  C.Print(string.format("market updated: %d items, %d listings. Loading item data...", #ids, rows))
  phase("items", 0, #ids)
  C.LoadItems(ids, function()
    for _, fn in ipairs(listeners) do pcall(fn) end
    phase("done", #ids, #ids); C.scan.items = #ids; C.scan.rows = rows
    C.Print("analysis ready. /kina opens the window.")
  end, function(i) C.scan.done = i end)
end

local function readAll()
  if reading or not AH or not AH.GetNumReplicateItems then return end
  local n = AH.GetNumReplicateItems() or 0
  if n <= 0 then return end
  -- the game keeps the last scan in memory: if it's the one Kina already read, it is
  -- old data, not a new scan (never stamp it as fresh)
  local sig = { n }
  for k = 0, n - 1, math.max(1, math.floor(n / 25)) do
    local _, _, cnt, _, _, _, _, _, _, bo, _, _, _, _, _, _, iid = AH.GetReplicateItemInfo(k)
    sig[#sig + 1] = tostring(iid) .. ":" .. tostring(bo) .. ":" .. tostring(cnt)
  end
  sig = table.concat(sig, ",")
  if C.market.sig == sig then
    phase("noreply")
    C.Print("the auction house only has the scan Kina already read: no new prices yet.")
    return
  end
  reading = true
  local i, acc = 0, {}
  local soldRows, soldBy = 0, {}
  phase("read", 0, n)
  C.Job(function()
    if not C.ahOpen then reading = false; phase("stopped"); C.Print("read stopped: auction house closed."); return true end
    local stop = math.min(i + CHUNK, n)
    while i < stop do
      local name, _, count, quality, _, _, _, _, _, buyout, _, _, _, _, _, saleStatus, id = AH.GetReplicateItemInfo(i)
      i = i + 1
      count = count or 1
      -- saleStatus 1 = already sold (waiting for the seller's mail): not buyable, so not a
      -- price, but counted: if the server lists them, they are real sales
      if id and saleStatus == 1 then soldRows = soldRows + 1; soldBy[id] = (soldBy[id] or 0) + (count or 1) end
      if id and count > 0 and buyout and buyout > 0 and saleStatus ~= 1 then
        local a = acc[id]
        if not a then a = { qty = 0, rows = 0, lv = {}, sx = {}, quality = quality }; acc[id] = a end
        -- exact price per item (a 50c stack of 200 is 0.25c each, not free)
        local unit = buyout / count
        -- random-suffix gear ("... of the Bear") shares the item ID but not the price:
        -- those rows are kept apart (they still count for disenchanting)
        local base = C.db.items[id] and C.db.items[id].name
        local lv = (base and type(name) == "string" and name ~= "" and name ~= base) and a.sx or a.lv
        if lv == a.lv then a.qty = a.qty + count; a.rows = a.rows + 1 else a.sxq = (a.sxq or 0) + count end
        local st = lv[unit]
        if not st then st = { 0, 0 }; lv[unit] = st end
        -- remember which roll it was ("of the Monkey") for the details panel
        if lv == a.sx and not st[3] and base and name:sub(1, #base) == base then st[3] = name:sub(#base + 2) end
        -- each roll's own cheapest price and count ("of the Eagle" = { cheapest, count })
        if lv == a.sx and base and name:sub(1, #base) == base then
          local suf = name:sub(#base + 2)
          a.sxn = a.sxn or {}
          local r = a.sxn[suf]
          if not r then a.sxn[suf] = { unit, count } else r[1] = math.min(r[1], unit); r[2] = r[2] + count end
        end
        st[1] = st[1] + count; st[2] = st[2] + 1
      end
    end
    C.scan.done = i
    if i >= n then
      reading = false
      if next(acc) then
        commit(acc, n)
        C.market.sig = sig
        C.market.soldRows, C.market.soldBy = soldRows, soldBy
        C.Print(string.format("scan read: %d listings%s.", n, soldRows > 0 and string.format(", %d marked SOLD (real sales data)", soldRows) or ", none marked sold"))
      end
      return true
    end
  end)
end

-- Scanning: nothing happens when the AH opens. Click Scan once and Kina keeps a full
-- scan going every 15 minutes (the game's limit) for as long as the AH stays open.
-- Closing the AH stops it; the next visit waits for your click again.
-- Settings "Keep scanning every 15 minutes" off = one scan per click.
local visit = 0
C.scanLoop = false
local function loopTick(mine)
  if mine ~= visit or not C.ahOpen or not C.scanLoop then return end
  local left = C.ScanCooldown()
  if left <= 0 and not reading then C.Scan(true) end
  -- check again when the limit runs out (and every 30s in case a scan was refused)
  C.After(math.max(5, math.min(30, (C.ScanCooldown() > 0) and C.ScanCooldown() + 3 or 30)), function() loopTick(mine) end)
end
function C.StartScanLoop()
  if not C.ahOpen then C.Print("open the auction house first."); return end
  if C.settings.autoScan == false then C.Scan(); return end
  if C.scanLoop then C.Scan(); return end
  C.scanLoop = true
  local left = C.ScanCooldown()
  if left > 0 then
    C.Print(string.format("auto-scan on: first scan in %d:%02d (the game allows one per 15 minutes), then every 15 minutes while the AH is open.",
      math.floor(left / 60), left % 60))
  else
    C.Print("auto-scan on: scanning now, then every 15 minutes while the AH is open.")
  end
  loopTick(visit)
end
C.On("AUCTION_HOUSE_SHOW", function()
  C.ahOpen = true
  visit = visit + 1
  C.scanLoop = false
end)
C.On("AUCTION_HOUSE_CLOSED", function() C.ahOpen = false; C.scanLoop = false; visit = visit + 1 end)
-- The snapshot arrives in pieces: wait until its size has been steady for 2 seconds
-- (same rule as ForeverForge) so a half-delivered scan is never read as the market.
local waiter = CreateFrame("Frame")
waiter:Hide()
C.GuardScript(waiter, "OnUpdate", "Market:244", function(self)
  local now = GetTime and GetTime() or 0
  local n = (AH and AH.GetNumReplicateItems and AH.GetNumReplicateItems()) or 0
  -- still growing = still arriving: keep waiting (up to 3 minutes of no change)
  if n ~= self.lastN then self.lastN, self.stableAt = n, now end
  if not C.ahOpen then self:Hide(); return end
  if n > 0 and now - self.stableAt >= 2 then self:Hide(); readAll()
  elseif now - self.stableAt > 180 then
    self:Hide(); phase("noreply")
    C.Print("the auction house sent no listings for that scan.")
  end
end)
C.On("REPLICATE_ITEM_LIST_UPDATE", function()
  local last = C.market.scanTime or 0
  ownRequest = false
  if reading or waiter:IsShown() then return end
  if C.Now() - last < 60 then return end -- same snapshot already read
  C.scanReply = C.Now()
  C.db.lastSnapshotSeen = C.Now()
  -- a fresh snapshot, whoever asked for it, starts the shared 15-minute limit
  C.db.lastReplicate = math.max(C.db.lastReplicate or 0, C.Now())
  waiter.lastN, waiter.stableAt, waiter.started = -1, GetTime and GetTime() or 0, GetTime and GetTime() or 0
  phase("request")
  waiter:Show()
end)

function C.ScanCooldown()
  local left = 900 - (C.Now() - (C.db.lastReplicate or 0))
  return left > 0 and left or 0
end

-- Own full scan. Note: shares the client's 15-minute limit with other scanners.
function C.Scan(auto)
  if not C.ahOpen then C.Print("open the auction house first."); return end
  local left = C.ScanCooldown()
  if left > 0 then C.Print(string.format("full scan cooldown: %d min left.", math.ceil(left / 60))); return end
  if not (AH and AH.ReplicateItems) then C.Print("this client has no full-scan API."); return end
  ownRequest = true
  local ok = pcall(AH.ReplicateItems)
  if not ok then ownRequest = false; phase("noreply"); C.Print("the auction house refused the scan request."); return end
  -- count the request now: a refused or silent request still uses the 15 minutes
  C.db.lastReplicate = C.Now()
  phase("request")
  -- no reply within 45s: the account's 15-minute scan was already used (another
  -- character, ForeverForge, ...). Say so, and let auto-scan retry in a minute
  -- instead of waiting a full 15 minutes on a scan that never came.
  local asked = C.Now()
  C.After(45, function()
    if (C.scanReply or 0) >= asked or reading then return end
    -- the game keeps the last full scan in memory for every addon: if another addon
    -- (ForeverForge, Auctionator) used the 15-minute limit, read the scan it made
    local have = AH.GetNumReplicateItems and AH.GetNumReplicateItems() or 0
    if have > 0 and C.ahOpen then
      C.scanReply = C.Now()
      -- how old is it? as old as the last snapshot this client was seen to receive
      -- (unknown: keep the age of Kina's own last scan, never "just now")
      C.stampOverride = C.db.lastSnapshotSeen or C.market.scanTime or 0
      waiter.lastN, waiter.stableAt, waiter.started = -1, GetTime and GetTime() or 0, GetTime and GetTime() or 0
      phase("request"); waiter:Show()
      C.Print("another addon used the 15-minute scan: reading the scan it made instead.")
      return
    end
    phase("noreply")
    C.Print("no scan came back: the game's 15-minute full-scan limit was probably used by another addon or character on your account. Trying again in a minute.")
    C.db.lastReplicate = C.Now() - 900 + 60
  end)
  C.Print(auto and "auto-scan: full scan requested (reading arrives in a few seconds)..." or "full scan requested...")
end

-- Price helpers ---------------------------------------------------------------
function C.MarketItem(id) return C.market.items[id] end

function C.ScanAgeMinutes()
  local t = C.market.scanTime
  return t and math.floor((C.Now() - t) / 60) or nil
end

-- Daily trend over the last `days` days: fractional change per day (log slope).
function C.Trend(id, days)
  local h = C.market.history[id]
  if not h then return nil end
  days = days or 5
  local today = day(C.Now())
  local xs, ys = {}, {}
  for d = today - days, today do
    local p = h[d]
    local v = p and (p[2] or p[1])
    if v and v > 0 then xs[#xs + 1] = d; ys[#ys + 1] = math.log(v) end
  end
  if #xs < 2 then return nil, #xs end
  local mx, my = 0, 0
  for k = 1, #xs do mx = mx + xs[k]; my = my + ys[k] end
  mx, my = mx / #xs, my / #xs
  local num, den = 0, 0
  for k = 1, #xs do num = num + (xs[k] - mx) * (ys[k] - my); den = den + (xs[k] - mx) ^ 2 end
  if den == 0 then return nil, #xs end
  return math.exp(num / den) - 1, #xs
end

-- 7-day median of daily medians (or nil)
function C.WeekMedian(id)
  local h = C.market.history[id]
  if not h then return nil end
  local today, vals = day(C.Now()), {}
  for d = today - 7, today do
    local p = h[d]; local v = p and (p[2] or p[1])
    if v then vals[#vals + 1] = v end
  end
  if #vals == 0 then return nil end
  table.sort(vals)
  return vals[math.ceil(#vals / 2)]
end
