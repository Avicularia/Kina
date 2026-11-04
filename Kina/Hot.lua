-- Kina: Hot. What makes the most gold per hour right now, at TODAY's prices.
-- Crafts: profit per item (sell now after the AH cut, minus what the reagents cost
-- now) x how fast that item leaves the auction house (listings gone per hour, from
-- scan to scan; you get about half of them). Spikes: today's price vs its 7-day
-- median. Also items you own that spiked: sell them now.
-- Unlike the Crafts tab (which uses the cautious week-median price), this list
-- shows spikes as they happen, so it says so: they can crash within the hour.
local _, C = ...
local H = {}
C.Hot = H

local SHARE = 0.5      -- your share of the buyers
local MAX_RATE = 300   -- crafts per hour one player can make and post

local function cut() return C.settings.ahCut or 0.05 end
-- today's sell price after the cut: the cheapest-20 price (one listing is not a market)
local function nowSell(id)
  local mi = C.MarketItem(id)
  local p = mi and (mi.d or mi.m)
  if not p then return nil end
  return p * (1 - cut()), mi
end
-- listings gone per hour (needs 2+ scans of it to mean anything)
local function goneRate(id)
  local v = C.market.vel and C.market.vel[id]
  if v and (v.n or 0) >= 2 and (v.v or 0) > 0 then return v.v end
end
H.GoneRate = goneRate
local function spikeOf(id)
  local mi = C.MarketItem(id)
  local wk = C.WeekMedian and C.WeekMedian(id)
  if mi and mi.m and wk and wk > 0 then return mi.m / wk end
end
H.Spike = spikeOf

local cache = {}
function H.Rows()
  local key = tostring(C.market.scanTime) .. "|" .. tostring(C.market.quick and C.market.quick.t)
  if cache.key == key and cache.t and (GetTime and GetTime() or 0) - cache.t < 20 then return cache.rows end
  local out = {}
  for spell, r in pairs(C.RecipeCatalog and C.RecipeCatalog() or {}) do
    if r.out and r.reagents and r.prof then
      local each, mi = nowSell(r.out)
      local outItem = C.Item(r.out)
      local bound = outItem and (outItem.bind == 1 or outItem.bind == 4)
      local rate = goneRate(r.out)
      -- a real market only: 10+ listed in 3+ auctions, 5+ gone an hour (one cancelled
      -- 100g listing is not demand)
      local liquid = mi and (mi.q or 0) >= 10 and (mi.n or 0) >= 3 and rate and rate >= 5
      if each and liquid and not bound then
        local cost, ok = 0, true
        for mat, q in pairs(r.reagents) do
          local c, how = C.BuyCost(mat)
          if not c or how == "est" then ok = false; break end
          cost = cost + c * q
        end
        local n = r.n or 1
        local profit = ok and (each - cost / n) or nil
        -- more than 20x the reagent cost is a broken price, not a deal
        if profit and profit > 0 and (cost <= 0 or profit <= 20 * cost / n) then
          local mine = math.min(rate * SHARE, MAX_RATE)
          local skill = C.MySkill(r.prof)
          local status = (C.IsKnown and C.IsKnown(spell)) and "learned" or (not skill and "none") or (skill >= (r.l or 0) and "can") or "low"
          local learn, learnKind, learnCost = C.LearnSource and C.LearnSource(r)
          out[#out + 1] = { kind = "Craft", id = r.out, spell = spell, name = r.name, prof = r.prof, n = n,
            profit = profit, cost = cost / n, sell = each, rate = rate, gph = profit * mine, spike = spikeOf(r.out),
            listed = mi.q or 0, status = status, need = r.l, skill = skill, learn = learn, learnKind = learnKind, learnCost = learnCost }
        end
      end
    end
  end
  -- what you own that spiked to 2x+ its week price: sell it while it lasts
  for id, have in pairs(C.Holdings and C.Holdings() or {}) do
    local sp = spikeOf(id)
    if have > 0 and sp and sp >= 2 then
      local each = nowSell(id)
      local ir = C.Item(id)
      if each and each > 0 and not (ir and (ir.bind == 1 or ir.bind == 4)) then
        out[#out + 1] = { kind = "Sell", id = id, name = ir and ir.name, held = have, sell = each, spike = sp,
          total = each * have, rate = goneRate(id) }
      end
    end
  end
  table.sort(out, function(a, b) return (a.gph or a.total or 0) > (b.gph or b.total or 0) end)
  cache = { key = key, rows = out, t = GetTime and GetTime() or 0 }
  return out
end

-- After each scan: tell the user about new spikes worth acting on (once per item per 2 hours).
C.OnMarket(function()
  if C.PUBLIC or C.settings.hotAlerts == false then return end
  local ok, rows = pcall(H.Rows)
  if not ok then return end
  C.db.hotSeen = C.db.hotSeen or {}
  local now, said = C.Now(), 0
  for _, r in ipairs(rows) do
    if said >= 3 then break end
    local big = (r.kind == "Craft" and (r.gph or 0) >= 10000 and (r.spike or 0) >= 2) or (r.kind == "Sell" and (r.total or 0) >= 5000)
    if big and now - (C.db.hotSeen[r.id] or 0) > 7200 then
      C.db.hotSeen[r.id] = now
      said = said + 1
      if r.kind == "Craft" then
        C.Print(string.format("|cffff8040HOT|r %s sells for %s (%.1fx its week price), costs %s to make: about %s/hour. See the Hot tab.",
          r.name or ("item " .. r.id), C.Money(r.sell), r.spike, C.Money(r.cost), C.Money(r.gph)))
      else
        C.Print(string.format("|cffff8040HOT|r you have %d %s: it sells for %s now (%.1fx its week price), %s for all. See the Hot tab.",
          r.held, r.name or ("item " .. r.id), C.Money(r.sell), r.spike, C.Money(r.total)))
      end
    end
  end
end)
