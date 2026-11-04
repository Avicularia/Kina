-- Kina: deal economics. One model ranks every opportunity on every page:
-- not ROI alone, but what a trade puts in your pocket for the cash, time and risk.
--
-- Deposits: a listing's deposit is a share of the item's VENDOR price. Forever's
-- deposits measured 4.7% / 18.8% / 56.4% for 2h / 8h / 24h; at your request Kina
-- caps the share at 5% for every duration. An item with no
-- vendor price costs nothing to list (0%): the only risk is waiting.
--
-- Sell-through: every full scan is compared with the one before. Cheap listings
-- that vanished between scans were (mostly) bought: units per hour = demand.
--
-- Confidence: the chance that ALL the units of a deal (or all the materials a
-- disenchant flip produces) sell before relisting deposits (or a falling price)
-- eat the profit. You get about half the demand while you're the cheapest.
--
-- Expected profit = units x profit - deposits lost on relists - one trade overhead
-- (what ~2 minutes of your time is worth). Score = expected x confidence, faster
-- sales first. Everything is calculated at every scan; filters only hide rows.
local _, C = ...
local E = {}
C.Econ = E
local floor, max, min, exp, log, sqrt = math.floor, math.max, math.min, math.exp, math.log, math.sqrt

local DUR_HOURS = { 2, 8, 24 } -- Forever auction durations (confirmed in game, Oct 16)
local DEFAULT_RATIO = { 0.047, 0.05, 0.05 }    -- 2h measured 4.7%; 8h/24h capped (see above)
local MAX_RATIO = 0.05                          -- deposits never counted above 5% of vendor price
-- longest you're willing to wait for everything to sell (Settings, default 3 days)
local function HORIZON() return math.max(0.5, C.settings.maxWaitDays or 3) * 24 end
local SHARE = 0.5                               -- your share of the buyers while cheapest

------------------------------------------------------------------ inputs
function E.GoldPerHour()
  local sum, n = 0, 0
  for i = 1, min(10, #C.db.sessions) do
    local s = C.db.sessions[i]
    if s.result and (s.result.secs or 0) >= 600 and (s.result.perHour or 0) > 0 then sum = sum + s.result.perHour; n = n + 1 end
  end
  if n >= 2 then return sum / n, true end
  local L = (UnitLevel and UnitLevel("player")) or 10
  return 40 * L * L, false
end

-- Copper a single trade must clear to be worth doing (Settings: Min profit per trade).
function E.Overhead()
  local fixed = C.settings.minProfit
  if fixed and fixed >= 0 then return fixed end
  return max(50, floor(E.GoldPerHour() * 120 / 3600))
end

function E.Duration() return C.settings.postDuration or 1 end
function E.DurationHours() return DUR_HOURS[E.Duration()] or 2 end

-- Deposit share of the vendor price for a posting duration (never above 5%).
function E.DepositRatio(dur)
  dur = dur or E.Duration()
  local mine = C.db.depositRatio and C.db.depositRatio[dur]
  if mine then return math.min(mine, MAX_RATIO), "measured, max 5%" end
  local ff = rawget(_G, "ForeverForgeAuctionDB")
  local r = type(ff) == "table" and type(ff.depositRatio) == "table" and ff.depositRatio[dur]
  if type(r) == "number" and r > 0 then return math.min(r, MAX_RATIO), "ForeverForge, max 5%" end
  return math.min(DEFAULT_RATIO[dur] or MAX_RATIO, MAX_RATIO), "default, max 5%"
end

-- Deposit (copper) to list `qty` of an item once, at your posting duration.
function E.DepositFor(id, qty)
  local r = C.Item(id)
  local vend = r and r.vend or 0
  if vend <= 0 then return 0 end
  return floor(vend * E.DepositRatio() * (qty or 1) + 0.5)
end

-- Measure the deposit share at the AH from something in your bags (same method as
-- ForeverForge): CalculateItemDeposit / vendor price, for each duration.
local function measure()
  local AH = C_AuctionHouse
  if not (AH and AH.CalculateItemDeposit and ItemLocation and C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerNumSlots) then return end
  for _, bag in ipairs(C.PlayerBags()) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isBound then
        local r = C.Item(info.itemID)
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if r and r.vend and r.vend >= 100 and loc and AH.IsSellItemValid and AH.IsSellItemValid(loc, false) then
          local ratios = {}
          for dur = 1, 3 do
            local ok, dep = pcall(AH.CalculateItemDeposit, loc, dur, 1)
            if ok and type(dep) == "number" and dep > 0 then ratios[dur] = dep / r.vend end
          end
          if next(ratios) then C.db.depositRatio = ratios; return end
        end
      end
    end
  end
end
C.On("AUCTION_HOUSE_SHOW", function() C.After(1, function() pcall(measure) end) end)

-- Units per hour the market buys (from scan-to-scan sell-through), or an estimate.
function E.Velocity(id)
  local v = C.market.vel and C.market.vel[id]
  if v and (v.n or 0) >= 2 then return max(v.v, 0.002), true end
  -- estimate from the book: gear sells about one piece a day per few listed,
  -- stackables faster. Labelled "~" wherever it is used.
  local mi = C.MarketItem(id)
  local r = C.Item(id)
  local gear = C.IsGear(r)
  local q = (mi and mi.q) or 0
  -- (conservative: ~6% of listed gear and ~12% of listed stackables sell per day)
  if gear then return max(0.01, min(0.25, q * 0.06 / 24)), false end
  return max(0.02, min(10, q * 0.12 / 24)), false
end

------------------------------------------------------------------ probability
-- P(Poisson(mean) >= n)
local function atLeast(n, mean)
  if n <= 0 then return 1 end
  if mean <= 0 then return 0 end
  if mean > 200 or n > 400 then
    -- normal approximation with continuity correction
    local z = (n - 0.5 - mean) / sqrt(mean)
    local t = 1 / (1 + 0.2316419 * math.abs(z))
    local d = 0.3989423 * exp(-z * z / 2)
    local p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
    return z > 0 and p or 1 - p
  end
  local term = exp(-mean)
  local cdf = term
  for k = 1, n - 1 do term = term * mean / k; cdf = cdf + term end
  return max(0, min(1, 1 - cdf))
end
E._atLeast = atLeast

-- How long profit survives while you wait: with a deposit, each expired listing
-- costs that deposit per unsold unit; with none, only a falling price hurts.
local function horizon(id, margin, depUnit, price)
  local hrs = E.DurationHours()
  local h
  if depUnit > 0 then
    local cycles = floor(margin / depUnit)
    h = max(1, cycles) * hrs
  else
    h = HORIZON()
  end
  local trend = C.Trend(id, 5)
  if trend and trend < -0.005 and price and price > 0 and margin < price then
    local days = log(1 - margin / price) / log(1 + trend)
    if days > 0 then h = min(h, days * 24) end
  end
  return min(h, HORIZON())
end

-- Price volatility from the last scans of the item (Market.lua keeps up to 10 scan
-- prices per item): per-hour drift and spread of the log price, plus the swing
-- (high - low) / average over those scans. Falls back to daily history, then to a
-- cautious 15%-a-day guess.
function E.Volatility(id)
  local pts = {}
  local ticks = C.market.ticks and C.market.ticks[id]
  if ticks and #ticks >= 3 then
    for _, t in ipairs(ticks) do pts[#pts + 1] = { t[1], t[2] } end
  else
    local h = C.market.history and C.market.history[id]
    if h then
      for d, p in pairs(h) do local v = p[2] or p[1]; if v and v > 0 then pts[#pts + 1] = { d * 86400, v } end end
      table.sort(pts, function(a, b) return a[1] < b[1] end)
    end
  end
  if #pts < 3 then return 0.15 / sqrt(24), 0, 0, nil, false end
  local sum, sq, hrs, hi, lo, avg = 0, 0, 0, 0, math.huge, 0
  for i = 2, #pts do
    local dt = max(0.25, (pts[i][1] - pts[i - 1][1]) / 3600)
    local r = log(pts[i][2] / pts[i - 1][2])
    sum = sum + r; sq = sq + r * r; hrs = hrs + dt
  end
  for _, p in ipairs(pts) do hi = max(hi, p[2]); lo = min(lo, p[2]); avg = avg + p[2] / #pts end
  local mu = sum / hrs
  local sigma = sqrt(max(0, sq / hrs - mu * mu * (hrs / (#pts - 1))))
  -- a short history understates risk: never trust less than 3%/day
  sigma = max(sigma, 0.03 / sqrt(24))
  return sigma, mu, #pts, (hi - lo) / avg, true
end

-- Standard normal CDF
local function phi(z)
  local t = 1 / (1 + 0.2316419 * math.abs(z))
  local d = 0.3989423 * exp(-z * z / 2)
  local p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
  return z > 0 and 1 - p or p
end

-- Chance the AVERAGE price you get while selling over `hours` stays above break-even
-- (price - margin), given the item's volatility and drift.
function E.PriceRisk(id, margin, price, hours)
  if not price or price <= 0 then return 1 end
  if margin <= 0 then return 0 end
  if margin >= price then return 1 end
  local sigma, mu = E.Volatility(id)
  local T = max(0.5, hours or 1)
  local cushion = log(price / (price - margin))
  local spread = sigma * sqrt(T / 3) -- average of a random walk over T
  return phi((cushion + mu * T / 2) / max(1e-6, spread))
end

-- Confidence that `n` units of `id` sell AND stay profitable: enough buyers within
-- the time the profit lasts, times the chance the price doesn't fall through your
-- break-even while you sell them. Also: hours to sell out, demand measured?, deposit.
function E.Confidence(id, n, margin, price)
  if n <= 0 then return 1, 0, true, 0, 1, 1 end
  local v, measured = E.Velocity(id)
  local rate = v * SHARE
  local depUnit = E.DepositFor(id, 1)
  local h = horizon(id, max(0, margin), depUnit, price)
  local demand = atLeast(n, rate * h)
  local sellOut = n / rate
  local priceOK = E.PriceRisk(id, margin, price, min(sellOut, h))
  return demand * priceOK, sellOut, measured, depUnit, demand, priceOK
end

-- Confidence you require before Kina recommends a quantity (Settings).
function E.Target() return (C.settings.minConfidence or 75) / 100 end

------------------------------------------------------------------ resale
-- Where a unit bought now can be relisted, and why (one rule for the Deals tab,
-- the detail panel and the tooltip):
--   1. ignore asking prices: anything above 3x the third-cheapest price tier
--   2. the next real competitor = the first tier above the cheapest that has
--      depth (2+ units for gear, 10% of the book for stackables), not a lone ask
--   3. list just under it, never above the 7-day median, and for gear never more
--      than 2x the cheapest listing (a bigger gap is usually a fantasy price)
-- Returns net (after the 5% cut), target, explanation; nil when there is no market.
function E.ResaleTarget(id)
  local mi = C.MarketItem(id)
  if not (mi and mi.m and mi.l and #mi.l >= 2) then return nil, nil, "fewer than two price tiers listed" end
  local L = mi.l
  local gear = C.IsGear(C.Item(id))
  local ceiling = L[min(3, #L)][1] * 3
  local need = gear and 2 or max(2, floor((mi.q or 0) * 0.1))
  local target, why
  for i = 2, #L do
    local p = L[i][1]
    if p > ceiling then break end
    local depth = 0
    for j = i, #L do if L[j][1] <= p * 1.25 then depth = depth + L[j][2] end end
    if depth >= need then target = p - 1; why = string.format("next real price %s (%d listed)", C.Money(p), depth); break end
  end
  if not target then return nil, nil, "no second price with real depth (only lone asking prices)" end
  local wk = C.WeekMedian(id)
  if wk and wk < target then target = wk; why = why .. ", capped at the 7-day median" end
  if gear and target > mi.m * 2 then target = mi.m * 2; why = why .. string.format(", capped at 2x the cheapest (%s)", C.Money(mi.m)) end
  if target <= mi.m then return nil, nil, "no gap between the cheapest and the next price" end
  return floor(target * (1 - C.settings.ahCut)), target, why
end
function E.ResaleNet(id) local net, target = E.ResaleTarget(id); return net, target end

-- Rough hours to sell one unit (used by Vendor and Crafts tabs).
function E.SellTime(id, price)
  local v = E.Velocity(id)
  local hours = min(72, 1 / max(0.01, v * SHARE))
  return hours, max(0.25, min(0.95, 1 - hours / 96))
end

------------------------------------------------------------------ evaluation
-- Simple form used by the Vendor and Crafts tabs.
function E.Evaluate(e)
  local units = max(1, e.units or 1)
  local cost, sell = e.cost or 0, e.sell or 0
  local odds = e.odds or 1
  local dep = e.deposit or 0
  local profit = sell - cost
  local overhead = (e.owned and dep == 0) and 0 or E.Overhead()
  local expected = (odds * profit - (1 - odds) * dep) * units - overhead
  e.profit, e.roi, e.expected, e.overhead = profit, (cost > 0) and profit / cost or nil, floor(expected), overhead
  e.capital = e.capital or cost * units
  e.score = expected / (1 + (e.hours or 0) / 24)
  e.worth = expected > 0
  return e
end

------------------------------------------------------------------ deals
-- Gear sells as whole auctions: a price step of q items in n auctions is bought in lots
-- of q/n, so a cap never splits one. Trade goods on Forever's AH are commodities, bought
-- by quantity (cheapest units first), so those can be split.
local wholeLots = false
local function lotsFor(id) local r = id and C.Item(id); wholeLots = (r and C.IsGear(r)) and true or false end
local function stepsUnder(ladder, limit, cap)
  local units, cost, top = 0, 0, nil
  for _, step in ipairs(ladder or {}) do
    if step[1] > limit or (cap and units >= cap) then break end
    local take = step[2]
    if cap and take > cap - units then
      local lot = wholeLots and math.max(1, math.ceil(step[2] / math.max(1, step[3] or 1))) or 1
      take = math.floor((cap - units) / lot) * lot
      if take <= 0 then break end
    end
    units = units + take; cost = cost + step[1] * take; top = step[1]
  end
  return units, cost, top
end
local function sortedCopy(...)
  local out = {}
  for _, ladder in ipairs({ ... }) do for _, s in ipairs(ladder or {}) do out[#out + 1] = s end end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- Finish a deal: confidence, deposits, cash needed, expected profit, score.
-- d.outputs = list of { id, qty, unitPrice } that must sell on the AH (nil = vendor)
local function finish(d)
  local units, profit = d.units, d.sell - d.cost
  d.profit = profit
  d.roi = d.cost > 0 and profit / d.cost or nil
  d.capital = floor(d.cost * units + 0.5)
  local conf, hours, measured, depUp, depLost = 1, 0, true, 0, 0
  local frac = d.sell > 0 and max(0, profit) / d.sell or 0 -- share of each sale that is profit
  for _, o in ipairs(d.outputs or {}) do
    local qty = max(1, floor(o.qty + 0.5))
    local margin = o.price * frac
    local c, h, m, depUnit, dem, pr = E.Confidence(o.id, qty, margin, o.price)
    conf = conf * c; hours = max(hours, h); measured = measured and m
    d.demand = (d.demand or 1) * dem; d.priceOK = (d.priceOK or 1) * pr
    local depAll = E.DepositFor(o.id, qty) -- stacks: the deposit is on the whole quantity
    depUp = depUp + depAll
    -- the average unit waits half the sell-out time: listings that expire meanwhile
    local relists = max(0, floor((h / 2) / E.DurationHours()))
    depLost = depLost + depAll * relists
  end
  d.confidence, d.hours, d.measured = conf, hours, measured
  d.demand, d.priceOK = d.demand or 1, d.priceOK or 1
  d.deposits = depUp
  d.depositsLost = depLost
  d.cash = d.capital + depUp
  d.overhead = E.Overhead()
  d.expected = floor(profit * units - depLost - d.overhead)
  d.worth = d.expected > 0 and conf >= E.Target() * 0.999
  -- passive = nothing (or next to nothing: under 1% of the profit) lost if it sits unsold
  d.passive = profit > 0 and (depUp == 0 or depUp < 0.01 * profit * units)
  d.score = d.expected * conf / (1 + hours / 48)
  -- passive: no deposit risk, so only profit and the chance it sells within your wait count
  d.passiveScore = d.expected * conf
  d.short = d.cash > ((GetMoney and GetMoney()) or math.huge)
  return d
end

-- Each deal = buy EVERY listing up to its "max price each" (still >= 10% profit per
-- item after the cut): Max each / Units / Buy cost are exactly the sniper settings.
-- passiveMode: only no-deposit deals, as many units as your gold pays for.
------------------------------------------------------------------ fake prices
-- Listings far above an item's real market (RMT / bot gold transfers, "just in
-- case" asks) are ignored everywhere: above 10x the third-cheapest price tier, or
-- above 20x what a vendor pays. Returns the cap (copper) or nil.
function E.PriceCap(id, ladder)
  local mi = ladder and { l = ladder } or C.MarketItem(id)
  local L = mi and mi.l
  if not (L and L[1]) then return nil end
  local cap = L[math.min(3, #L)][1] * 10
  local r = C.Item(id)
  if r and r.vend and r.vend > 0 then cap = math.min(cap, math.max(r.vend * 20, L[1][1] * 2)) end
  return cap
end
function E.CleanLadder(id, ladder)
  local cap = E.PriceCap(id, ladder)
  if not cap then return ladder or {} end
  local out = {}
  for _, st in ipairs(ladder or {}) do if st[1] <= cap then out[#out + 1] = st end end
  return out
end

------------------------------------------------------------------ "now" prices
-- What a material sells for right now: just under its cheapest real listing, after
-- the 5% cut. Only for materials with a real book (3+ listings); otherwise nil.
function E.MatNow(id)
  local mi = C.MarketItem(id)
  if not (mi and mi.m and (mi.n or 0) >= 3) then return nil end
  local L = E.CleanLadder(id, mi.l)
  if not L[1] then return nil end
  return math.floor(math.max(1, L[1][1] - 1) * (1 - C.settings.ahCut))
end

-- Disenchant value at today's material prices (no history, no forecasts).
function E.DEValueNow(id)
  local outs = C.DEOutcomes(id)
  if not outs then return nil end
  local ev, mats = 0, {}
  for _, o in ipairs(outs) do
    local v = 0
    for mat, q in pairs(o.mats) do
      local unit = E.MatNow(mat)
      if not unit then return nil, mat end
      v = v + unit * q
      mats[mat] = (mats[mat] or 0) + o.p * q
    end
    ev = ev + o.p * v
  end
  return math.floor(ev), mats
end

------------------------------------------------------------------ deals (now)
-- Deals = trades you can check against prices on screen right now:
--   AH->Vendor  buy listings a merchant pays more for (sold the moment you visit one)
--   Disenchant  buy gear, disenchant, sell the materials just under their cheapest
--               listing today
-- No forecasts, no "sells in", no confidence: those need history (Investments tab).
local function finishNow(d)
  d.profit = d.sell - d.cost
  d.roi = d.cost > 0 and d.profit / d.cost or nil
  d.capital = floor(d.cost * d.units + 0.5)
  d.deposits = 0
  for mat, perUnit in pairs(d.mats or {}) do d.deposits = d.deposits + E.DepositFor(mat, perUnit * d.units) end
  d.cash = d.capital + d.deposits
  d.overhead = E.Overhead()
  d.expected = floor(d.profit * d.units - d.overhead)
  d.worth = d.expected > 0
  d.passive = d.profit > 0 and (d.deposits == 0 or d.deposits < 0.01 * d.profit * d.units)
  d.score = d.expected
  d.short = d.cash > ((GetMoney and GetMoney()) or math.huge)
  return d
end

------------------------------------------------------------------ guardian
-- Small samples: a disenchant deal can be profitable on AVERAGE only because of a
-- rare drop (a 5% shard). Buy 20 and you may never see it. Guardian = the chance
-- you end up with less gold than you paid, for a given number bought, from the
-- disenchant odds and the material amounts at today's prices.
local function deValues(id)
  local outs = C.DEOutcomes(id, true)
  if not outs then return nil end
  local list, tp = {}, 0
  for _, o in ipairs(outs) do
    if (o.p or 0) > 0 then
      local base = 0
      for mat, q in pairs(o.mats) do
        local u = E.MatNow(mat); if not u then return nil end
        base = base + u * q
      end
      if o.mat and o.lo and o.hi and o.hi > o.lo then
        local u, k, avgq = E.MatNow(o.mat), o.hi - o.lo + 1, (o.lo + o.hi) / 2
        for q = o.lo, o.hi do list[#list + 1] = { p = o.p / k, v = base + u * (q - avgq) } end
      else list[#list + 1] = { p = o.p, v = base } end
      tp = tp + o.p
    end
  end
  if tp <= 0 then return nil end
  for _, x in ipairs(list) do x.p = x.p / tp end
  return list
end

-- { [n] = chance of losing money when you buy the cheapest n } for each n in ns
function E.LossChance(id, ladder, maxEach, ns)
  local vals = deValues(id)
  if not vals or #ns == 0 then return nil end
  table.sort(ns)
  local mu, m2, vmax = 0, 0, 0
  for _, x in ipairs(vals) do mu = mu + x.p * x.v; m2 = m2 + x.p * x.v * x.v; if x.v > vmax then vmax = x.v end end
  if vmax <= 0 then return nil end
  local var = max(0, m2 - mu * mu)
  -- (the odds for n bought use the average price of the cheapest n, lots or not)
  local function costOf(n)
    local u, c = 0, 0
    for _, step in ipairs(ladder or {}) do
      if step[1] > maxEach or u >= n then break end
      local take = min(step[2], n - u); u = u + take; c = c + step[1] * take
    end
    if u < n then return nil end
    return c
  end
  local res, need = {}, {}
  for _, n in ipairs(ns) do need[n] = true end
  -- exact (value buckets) up to 60 items, normal approximation beyond
  local exactTo = min(ns[#ns], 60)
  -- buckets of w copper; each result is split between the two nearest buckets so
  -- the average stays exact (rounding a common 6s dust to 0 made the odds look awful)
  local w = max(1, exactTo * vmax / 400)
  local steps = {}
  for _, x in ipairs(vals) do
    local q = x.v / w
    local lo = floor(q)
    local f = q - lo
    if f > 0 then steps[#steps + 1] = { lo + 1, x.p * f } end
    if f < 1 then steps[#steps + 1] = { lo, x.p * (1 - f) } end
  end
  local dist = { [0] = 1 }
  for k = 1, exactTo do
    local nd = {}
    for j, pj in pairs(dist) do
      for _, st in ipairs(steps) do local t = j + st[1]; nd[t] = (nd[t] or 0) + pj * st[2] end
    end
    dist = nd
    if need[k] then
      local c = costOf(k)
      if c then
        local lim, pl = c / w, 0
        for j, pj in pairs(dist) do if j < lim then pl = pl + pj end end
        res[k] = min(1, pl)
      end
    end
  end
  for _, n in ipairs(ns) do
    if n > exactTo then
      local c = costOf(n)
      if c then
        local sd = math.sqrt(var * n)
        res[n] = sd > 0 and phi((c - mu * n) / sd) or ((mu * n < c) and 1 or 0)
      end
    end
  end
  return res
end

-- How many you can pay for with the gold on you (cheapest first, up to maxEach)
local function affordable(ladder, maxEach, gold)
  local n, spent = 0, 0
  for _, step in ipairs(ladder or {}) do
    if step[1] > maxEach then break end
    local take = min(step[2], floor((gold - spent) / step[1]))
    if take < step[2] and wholeLots then -- whole auctions only (gear)
      local lot = math.max(1, math.ceil(step[2] / math.max(1, step[3] or 1)))
      take = floor(take / lot) * lot
    end
    if take <= 0 then break end
    n, spent = n + take, spent + take * step[1]
    if take < step[2] then break end
  end
  return n
end

local GRID = { 5, 10, 20, 30, 40, 50, 60, 80, 100, 150, 200, 300 }
local function guard(d, gold)
  if d.kind ~= "Disenchant" or not d.ladder then d.loss = 0; d.lossN = d.units; return end
  lotsFor(d.id)
  local mine = affordable(d.ladder, d.maxEach, gold)
  local n = (mine > 0) and min(d.units, mine) or d.units
  local ns, seen = {}, {}
  local function addN(k) if k >= 1 and k <= d.available and not seen[k] then seen[k] = true; ns[#ns + 1] = k end end
  addN(n); addN(d.units)
  for _, k in ipairs(GRID) do addN(k) end
  local res = E.LossChance(d.id, d.ladder, d.maxEach, ns)
  if not res then return end
  d.loss, d.lossN, d.lossGrid = res[n], n, res
  for _, k in ipairs(ns) do if res[k] and res[k] <= 0.05 then d.safeN = k; break end end
end

function E.NowDealsUncached(passiveMode)
  local out = {}
  local canDE = C.CanDisenchantAny and C.CanDisenchantAny()
  local gold = (GetMoney and GetMoney()) or math.huge
  -- a finished Quick scan newer than the full scan: listings it no longer sees were
  -- bought; anything cheaper than the full scan saw is new
  local Q = C.market.quick
  local fresh = Q and Q.complete and (Q.t or 0) > (C.market.scanTime or 0) and Q.items or nil
  local vendorDone = {}
  local function add(d, ladder, maxEach, cap)
    lotsFor(d.id)
    if fresh then
      local e = fresh[d.id]
      if not e or not e.m or e.m > maxEach then return end
      local trimmed = {}
      for _, s in ipairs(ladder) do if s[1] >= e.m then trimmed[#trimmed + 1] = s end end
      if not trimmed[1] or trimmed[1][1] > e.m then table.insert(trimmed, 1, { e.m, 1, 1 }) end
      ladder = trimmed
      d.quick = true
    end
    if d.kind == "AH->Vendor" then vendorDone[d.id] = true end
    if passiveMode or C.settings.dealAfford then
      local all, allCost = stepsUnder(ladder, maxEach)
      if allCost > gold and all > 0 then cap = min(cap or math.huge, max(1, floor(all * gold / allCost))) end
    end
    local units, cost, top = stepsUnder(ladder, maxEach, cap)
    if units <= 0 then return end
    d.units, d.cost, d.buy, d.maxEach = units, cost / units, top, maxEach
    d.available = stepsUnder(ladder, maxEach)
    d.ladder = ladder
    out[#out + 1] = finishNow(d)
  end
  for id, own in pairs(C.market.items) do
    local mi = C.MarketItem(id) or own
    -- a partner's newer scan from an older Kina has no listings: use your own for those
    if not (mi.l and mi.l[1]) and not mi.sl and own.l and own.l[1] then mi = own end
    local r = C.Item(id)
    local v, how = C.VendorPrice(id, true)
    if v and v > 0 and mi.l then
      add({ id = id, kind = "AH->Vendor", sell = v, note = "vendor pays " .. C.Money(v) .. " (" .. (how == "seen" and "seen at a merchant" or "game's sell price minus Kina's 10% safety margin") .. ")" },
        mi.l, floor(v / 1.1))
    end
    if C.IsGear(r) and canDE and C.CanDE(id) == true and r.il then
      local ev, mats = E.DEValueNow(id)
      if ev and ev > 0 then
        local maxEach = floor(ev / 1.1)
        -- today's prices only hold for about as many materials as are listed today:
        -- never more disenchants than would double any material's listed quantity
        local cap, limiting = math.huge, nil
        for mat, per in pairs(mats) do
          local listed = (C.MarketItem(mat) or {}).q or 0
          if per > 0 then
            local n = floor(listed / per)
            if n < cap then cap, limiting = n, mat end
          end
        end
        local limNote = ""
        if cap < math.huge and limiting then
          local lr = C.Item(limiting)
          limNote = string.format("; at most %d so your %s don't outnumber today's listings", cap, (lr and lr.name) or "materials")
        end
        local need = C.DESkillNeeded(r.il or 0)
        add({ id = id, kind = "Disenchant", sell = ev, mats = mats, needSkill = need,
          note = string.format("materials valued at today's cheapest listings; disenchanter: %s%s",
            C.DisenchanterText and C.DisenchanterText() or "?", limNote) },
          sortedCopy(mi.l, mi.sl), maxEach, (cap < math.huge) and max(0, cap) or nil)
      end
    end
  end
  -- new listings under vendor price that only the Quick scan has seen
  for id, e in pairs(fresh or {}) do
    if not vendorDone[id] and e.m then
      local v, how = C.VendorPrice(id, true)
      if v and v > 0 and e.m <= floor(v / 1.1) then
        add({ id = id, kind = "AH->Vendor", sell = v, note = "new listing (Quick scan): vendor pays " .. C.Money(v) .. ". Quick scan sees the cheapest one only: check how many are at this price." },
          { { e.m, 1, 1 } }, floor(v / 1.1))
      end
    end
  end
  local now = C.Now()
  local kept = {}
  local skill = C.DisenchantSkill and C.DisenchantSkill() or 0
  for _, d in ipairs(out) do
    -- your enchanter can't disenchant it yet: listed greyed at the bottom, not advised
    guard(d, gold)
    if d.loss then
      d.score = d.expected * (1 - d.loss)
      if d.loss >= 0.5 then d.worth = false end
    end
    if d.needSkill and d.needSkill > (skill or 0) then
      d.tooHigh = true; d.worth = false; d.score = d.expected - 1e12
    end
    local _, who, t = C.MarketItem(d.id)
    if d.quick and C.market.quick then t, who = C.market.quick.t, nil end
    d.priceAge = t and floor((now - t) / 60) or nil
    d.priceFrom = who
    d.stale = d.priceAge and d.priceAge > 20
    if not passiveMode or d.passive then kept[#kept + 1] = d end
  end
  table.sort(kept, function(a, b) return a.expected > b.expected end)
  return kept
end

------------------------------------------------------------------ investments
-- Investments need history: an item qualifies only after Kina has seen it on
-- enough days and scans AND has seen listings actually sell (vanish) between scans.
function E.DataStatus(id)
  local days = 0
  for _ in pairs(C.market.history[id] or {}) do days = days + 1 end
  local scans = C.market.seen and C.market.seen[id] or 0
  local v = C.market.vel and C.market.vel[id]
  local sales = v and (v.n or 0) >= 3 and (v.v or 0) > 0
  local needDays, needScans = C.settings.investDays or 7, C.settings.investScans or 10
  return days >= needDays and scans >= needScans and sales, days, scans, sales, needDays, needScans
end

local cache = {}
local function cached(name, fn, passiveMode)
  local key = table.concat({ name, tostring(passiveMode), tostring(C.market.scanTime), tostring(C.settings.minConfidence),
    tostring(C.settings.maxWaitDays), tostring(C.settings.postDuration), tostring(C.settings.deFriend),
    tostring(C.settings.minProfit), tostring(C.settings.investDays), tostring(C.settings.investScans),
    tostring(GetMoney and floor(GetMoney() / 10000)), tostring(C.market.quick and C.market.quick.t), tostring(C.settings.dealAfford), tostring(C.settings.matLowest), tostring(C.settings.deMine) }, "|")
  local now = GetTime and GetTime() or 0
  local c = cache[name .. tostring(passiveMode)]
  if c and c.key == key and now - c.t < 20 then return c.rows end
  local rows = fn(passiveMode)
  cache[name .. tostring(passiveMode)] = { key = key, t = now, rows = rows }
  return rows
end
function E.Deals(passiveMode) return cached("now", E.NowDealsUncached, passiveMode) end
function E.Investments() return cached("invest", E.InvestUncached) end

function E.InvestUncached(passiveMode)
  local out = {}
  local canDE = C.CanDisenchantAny and C.CanDisenchantAny()
  local age = C.ScanAgeMinutes and C.ScanAgeMinutes()
  local gold = (GetMoney and GetMoney()) or math.huge
  local function add(d, ladder, maxEach, cap)
    lotsFor(d.id)
    if passiveMode or C.settings.dealAfford then
      -- spend what you have: units capped by gold
      local all, allCost = stepsUnder(ladder, maxEach, cap)
      if allCost > gold and all > 0 then cap = max(1, floor(all * gold / allCost)) end
    end
    local all = stepsUnder(ladder, maxEach, cap)
    if all <= 0 then return end
    local outputsFor = d.outputsFor; d.outputsFor = nil
    local function at(u)
      local e = {}
      for k, v in pairs(d) do e[k] = v end
      local units, cost, top = stepsUnder(ladder, maxEach, u)
      e.units, e.cost, e.buy, e.maxEach = units, cost / units, top, maxEach
      if outputsFor then e.outputs = outputsFor(units) end
      return finish(e)
    end
    -- the most units that still reach the confidence you require (binary search;
    -- confidence only falls as the quantity grows)
    local best = at(all)
    if best.confidence < E.Target() and all > 1 then
      local lo, hi = 1, all
      local first = at(1)
      if first.confidence >= E.Target() then
        best = first
        while hi - lo > 1 do
          local mid = floor((lo + hi) / 2)
          local e = at(mid)
          if e.confidence >= E.Target() then lo, best = mid, e else hi = mid end
        end
      else
        best = first -- not even one meets the target: shown greyed, as not worth it
      end
    end
    best.available = all
    best.availableCost = select(2, stepsUnder(ladder, maxEach, all))
    out[#out + 1] = best
  end
  for id, own in pairs(C.market.items) do
    local mi = C.MarketItem(id) or own
    local r = C.Item(id)
    local gear = C.IsGear(r)
    -- resale under the going rate: only items with enough history and seen sales
    if mi.m and (mi.n or 0) >= 5 and mi.l and #mi.l >= 2 and E.DataStatus(id) then
      local net, target, why = E.ResaleTarget(id)
      if net and target then
        add({ id = id, kind = "Resale", sell = net, note = "relist at " .. C.Money(target) .. " (" .. why .. ")",
          outputsFor = function(units) return { { id = id, qty = units, price = net } } end },
          mi.l, floor(net / 1.15), max(1, floor((mi.q or 1) / 4)))
      end
    end
  end
  -- merchant -> AH (merchant stock; sell into ~10% of what is listed)
  if C.VendorFlips then
    for _, f in ipairs(C.VendorFlips()) do
      if E.DataStatus(f.id) then
      local listed = (C.MarketItem(f.id) or {}).q or 1
      local units = max(1, floor(listed / 10))
      if f.stock then units = min(units, f.stock) end
      if passiveMode then units = max(1, min(units, floor(gold / max(1, f.buy)))) end
      local sell = floor(f.ah * (1 - C.settings.ahCut))
      out[#out + 1] = finish({ id = f.id, kind = "Merchant->AH", cost = f.buy, buy = f.buy, maxEach = f.buy, sell = sell,
        units = units, note = "from " .. (f.who or "?") .. ", " .. (f.where or "?"),
        outputs = { { id = f.id, qty = units, price = sell } } })
      end
    end
  end
  local kept = {}
  for _, d in ipairs(out) do
    -- "old" = the prices this row uses (yours or a party member's scan) are 20+ min old
    local _, who, t = C.MarketItem(d.id)
    d.priceAge = t and math.floor((C.Now() - t) / 60) or age
    d.priceFrom = who
    d.stale = d.priceAge and d.priceAge > 20
    if not passiveMode or d.passive then kept[#kept + 1] = d end
  end
  if passiveMode then table.sort(kept, function(a, b) return a.passiveScore > b.passiveScore end)
  else table.sort(kept, function(a, b) return a.score > b.score end) end
  return kept
end

-- "now", "40m", "6h", "3d"
function E.Hours(h)
  if not h or h <= 0.05 then return "now" end
  if h < 1 then return floor(h * 60) .. "m" end
  if h < 48 then return floor(h + 0.5) .. "h" end
  return floor(h / 24 + 0.5) .. "d"
end

-- old name, kept for any caller: deposit per unit of a generic listing
function E.Deposit() return 0 end
