-- Kina: bag advisor (sell now / hold / vendor / disenchant) and stockpile list.
local _, C = ...
local CT = C_Container

local function bagItems()
  local out = {}
  if not (CT and CT.GetContainerNumSlots and CT.GetContainerItemInfo) then return out end
  for _, bag in ipairs(C.PlayerBags()) do
    for slot = 1, CT.GetContainerNumSlots(bag) or 0 do
      local info = CT.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local e = out[info.itemID]
        if not e then e = { id = info.itemID, count = 0, bound = false }; out[info.itemID] = e end
        e.count = e.count + (info.stackCount or 1)
        e.bound = e.bound or info.isBound
      end
    end
  end
  return out
end
C.BagItems = bagItems

function C.DaysSinceLaunch()
  return (C.Now() - C.settings.launchTime) / 86400
end

-- Launch prior for a trade good: expected daily change, or nil.
local function launchPrior(r)
  local d = C.DaysSinceLaunch()
  if d < 0 or d > 21 or not r or r.cls ~= 7 then return nil end
  local lvl = (r.rl and r.rl > 0) and r.rl or r.il or 60
  for _, t in ipairs(C.Data.launchDecay) do if lvl <= t.maxLevel then return t.perDay end end
end

-- One recommendation per item stack in your bags.
function C.Advise(e)
  local id, n = e.id, e.count
  local r = C.Item(id)
  local route, unit, det = C.BestRoute(id, n)
  if e.bound and route == "AUCTION" then route = "VENDOR"; unit = det.vendor or 0 end
  local stock = C.db.stock[id]
  local row = { id = id, count = n, route = route, unit = unit, total = (unit or 0) * n, det = det }
  local trend, points = C.Trend(id, 5)
  row.trend, row.points = trend, points
  if stock and stock.sellAt and det.ah and det.ah < stock.sellAt * 0.95 then
    row.action = "HOLD"
    row.why = "stockpile: target " .. C.Money(stock.sellAt)
  elseif route == "AUCTION" then
    local prior = launchPrior(r)
    if trend and trend <= -0.03 then
      row.action = "SELL NOW"; row.why = string.format("falling %.0f%%/day", -trend * 100)
    elseif trend and trend >= 0.05 then
      row.action = "SELL (can wait)"; row.why = string.format("rising %.0f%%/day", trend * 100)
    elseif prior then
      row.action = "SELL NOW"; row.why = string.format("launch prior: ~%.0f%%/day drop", -prior * 100)
    else
      row.action = "SELL"; row.why = "steady"
    end
    if det.vendor and det.vendor > 0 and det.ah and det.ah < det.vendor * 1.25 then
      row.why = row.why .. "; AH barely beats vendor"
    end
  elseif route == "DISENCHANT" then
    row.action = "DISENCHANT"
    row.why = det.de and ("worth " .. C.Money(det.de.ev) .. " in mats") or ""
  elseif route == "VENDOR" then
    row.action = "VENDOR"; row.why = (C.VendorPrice(id)) and "vendor pays more" or ""
  else
    row.action = "KEEP"; row.why = "no sale value found"
  end
  if C.Data.scarce[id] then row.why = row.why .. "; scarce material" end
  return row
end

function C.AdviseBags()
  local rows, totals = {}, {}
  for _, e in pairs(bagItems()) do
    local row = C.Advise(e)
    rows[#rows + 1] = row
    totals[row.action] = (totals[row.action] or 0) + row.total
  end
  local order = { ["SELL NOW"] = 1, ["SELL"] = 2, ["SELL (can wait)"] = 3, ["DISENCHANT"] = 4, ["VENDOR"] = 5, ["HOLD"] = 6, ["KEEP"] = 7 }
  table.sort(rows, function(a, b)
    local oa, ob = order[a.action] or 9, order[b.action] or 9
    if oa ~= ob then return oa < ob end
    return a.total > b.total
  end)
  return rows, totals
end

------------------------------------------------------------------ stockpile
function C.SeedStock()
  for id, s in pairs(C.Data.stockSeeds) do
    if not C.db.stock[id] and not (C.db.stockRemoved and C.db.stockRemoved[id]) then
      C.db.stock[id] = { buyUnder = s.buyUnder, sellAt = s.sellAt, note = s.note, added = C.Now() }
    end
  end
end
C.On("INIT", C.SeedStock)

function C.StockRows()
  local rows = {}
  for id, s in pairs(C.db.stock) do
    local mi = C.MarketItem(id)
    local under = 0
    if mi and mi.l and s.buyUnder then
      for _, step in ipairs(mi.l) do if step[1] <= s.buyUnder then under = under + step[2] end end
    end
    rows[#rows + 1] = { id = id, s = s, low = mi and mi.m, qty = mi and mi.q, under = under,
      week = C.WeekMedian(id), trend = (C.Trend(id, 5)), have = C.BagCount(id) }
  end
  table.sort(rows, function(a, b) return a.under > b.under end)
  return rows
end

-- Track list = the stockpile table; targets are optional.
function C.IsTracked(id) return C.db.stock[id] ~= nil end
function C.ToggleTrack(id)
  if C.db.stock[id] then
    C.db.stock[id] = nil
    C.db.stockRemoved = C.db.stockRemoved or {}; C.db.stockRemoved[id] = true
    C.Print("stopped tracking " .. ((C.Item(id) or {}).name or id) .. ".")
  else
    C.db.stock[id] = { note = "", added = C.Now() }
    if C.db.stockRemoved then C.db.stockRemoved[id] = nil end
    C.Print("tracking " .. ((C.Item(id) or {}).name or id) .. ". Set alert/hold prices on the Settings tab.")
  end
end

function C.BagCount(id)
  local n = 0
  for _, e in pairs(bagItems()) do if e.id == id then n = n + e.count end end
  return n
end

C.OnMarket(function()
  for _, row in ipairs(C.StockRows()) do
    if row.under > 0 then
      local r = C.Item(row.id)
      C.Print(string.format("|cff7CFC00STOCK ALERT|r %s: %d listed at or under %s (low %s).",
        (r and r.name) or ("item " .. row.id), row.under, C.Money(row.s.buyUnder), C.Money(row.low)))
    end
  end
end)
