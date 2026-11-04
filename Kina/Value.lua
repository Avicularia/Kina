-- Kina: what an item is worth, and the deals in the latest scan.
-- Every number is an estimate with its basis shown; nothing is hidden for being
-- unverified. Low confidence widens the range instead of removing the row.
local _, C = ...
local D = C.Data

------------------------------------------------------------------ disenchanting
local function tier(list, il)
  for _, t in ipairs(list) do if il >= t[1] and il <= t[2] then return t end end
end

-- WoW Forever (like original Classic): any enchanter can disenchant any green,
-- blue or purple, even at Enchanting 1. The skill-per-item-level gate only came
-- with The Burning Crusade. D.deSkillGate = true would bring that table back.
function C.DESkillNeeded(il)
  if not D.deSkillGate then return 1 end
  for _, s in ipairs(D.deSkill) do if il <= s[1] then return s[2] end end
  return 300
end

-- Can this item be disenchanted at all? (gear, green to epic, not a known exception)
function C.CanDE(id)
  if D.noDE[id] or C.db.noDE[id] then return false, "game refuses" end
  local r, full = C.Item(id)
  if not (r and C.IsGear(r)) then return false, "not gear" end
  if r.eq == "INVTYPE_BODY" or r.eq == "INVTYPE_TABARD" then return false, "shirt/tabard" end
  if not full then return nil, "item data loading" end
  if not r.q or r.q < 2 or r.q > 4 then return false, "quality" end
  if not r.il or r.il < 5 then return false, "item level" end
  return true
end

-- Observations are pooled by quality, Classic item-level band and weapon/armor.
-- The level the Forever disenchanting table is keyed by: the item's required level
-- (item level - 5 when it has none, which is how greens line up).
function C.DELevel(r)
  if r.rl and r.rl > 0 then return r.rl end
  return math.max(1, (r.il or 1) - 5)
end

function C.DETierKey(r)
  local lo = math.floor(((r.il or 0) - 1) / 5) * 5 + 1
  return (r.q or 0) .. ":" .. lo .. ":" .. ((r.cls == 2) and "w" or "a")
end

-- Outcome list: { {p=probability, mats={[id]=qty}}, ... } using average quantities.
-- The Forever table by default. With "Disenchant values from my own results" on
-- (Settings), your observed average replaces it once you have 100+ in a band.
-- tableOnly: always the table (the Guardian needs the odds of each result).
C.DE_OBS_MIN = 100
function C.DEOutcomes(id, tableOnly)
  local r = C.Item(id)
  if not (r and r.il and r.q) then return nil end
  local obs = C.db.deObs and C.db.deObs[C.DETierKey(r)]
  if not tableOnly and C.settings.deMine and obs and obs.n >= C.DE_OBS_MIN then
    local mats = {}
    for mat, n in pairs(obs.mats) do mats[mat] = n / obs.n end
    return { { p = 1, mats = mats } }, "observed"
  end
  local il, out = r.il, {}
  if r.q == 2 then
    local t = tier(D.deGreen, C.DELevel(r)); if not t then return nil end
    local pct = (r.cls == 2) and t[11] or t[10]
    out[#out + 1] = { p = pct[1], mats = { [t[3]] = (t[6] + t[7]) / 2 }, mat = t[3], lo = t[6], hi = t[7] }
    out[#out + 1] = { p = pct[2], mats = { [t[4]] = (t[8] + t[9]) / 2 }, mat = t[4], lo = t[8], hi = t[9] }
    if t[5] and pct[3] > 0 then out[#out + 1] = { p = pct[3], mats = { [t[5]] = 1 } } end
  elseif r.q == 3 then
    local t = tier(D.deRare, C.DELevel(r)); if not t then return nil end
    out[#out + 1] = { p = t[4], mats = { [t[3]] = 1 } }
    if t[5] then out[#out + 1] = { p = t[6], mats = { [t[5]] = 1 } } end
  elseif r.q == 4 then
    local t = tier(D.deEpic, il); if not t then return nil end
    out[#out + 1] = { p = 1, mats = { [t[3]] = (t[4] + t[5]) / 2 }, mat = t[3], lo = t[4], hi = t[5] }
  end
  return out
end

-- Net copper per unit when SELLING a material: depth price of 20 units vs the
-- week median, whichever is lower, after the AH cut; vendor if that pays more.
function C.MatExit(id)
  local mi = C.MarketItem(id)
  local base = mi and (mi.d or mi.m)
  local wk = C.WeekMedian(id)
  if C.settings.matLowest and mi and mi.m then
    base = mi.m -- like ForeverForge: today's cheapest listing
  elseif base and wk then base = math.min(base, wk) elseif wk then base = wk end
  local ah = base and math.floor(base * (1 - C.settings.ahCut)) or nil
  local v = C.VendorPrice(id, true) or 0
  if not ah then return (v > 0) and v or nil, "vendor" end
  if v > ah then return v, "vendor" end
  return ah, "ah"
end

-- Expected net value of disenchanting one item, plus worst and best outcome.
function C.DEValue(id)
  local outs = C.DEOutcomes(id)
  if not outs then return nil end
  local ev, lo, hi, missing = 0, nil, nil, nil
  for _, o in ipairs(outs) do
    local v = 0
    for mat, qty in pairs(o.mats) do
      local unit = C.MatExit(mat)
      if not unit then missing = mat; unit = 0 end
      v = v + unit * qty
    end
    o.value = v
    ev = ev + o.p * v
    lo = lo and math.min(lo, v) or v
    hi = hi and math.max(hi, v) or v
  end
  return { ev = math.floor(ev), lo = lo, hi = hi, outcomes = outs, missing = missing }
end

-- Chance of losing money when buying at `cost` and disenchanting.
function C.DELossChance(dv, cost)
  local p = 0
  for _, o in ipairs(dv.outcomes) do if o.value < cost then p = p + o.p end end
  return p
end

-- Who can disenchant: this character, another of your characters, or a friend you
-- trade with (/kina defriend). Returns the best Enchanting skill available.
function C.DisenchantSkill()
  local best
  for _, ch in pairs(C.db.chars or {}) do
    local s = ch.prof and ch.prof.Enchanting
    if s and (not best or s > best) then best = s end
  end
  if C.settings.deFriend then best = math.max(best or 0, C.settings.deFriend) end
  -- an enchanter in your group who runs Kina (your farm partner can disenchant the drops)
  local S = C.Share
  for _, a in pairs(S and S.DB and S.DB().authors or {}) do
    local sk = a.char and a.char.profs and a.char.profs.Enchanting
    if sk and a.seen and C.Now() - a.seen < 1800 and C.InGroupName and C.InGroupName(a.name) then best = math.max(best or 0, sk) end
  end
  return best
end
function C.CanDisenchantAny() return C.DisenchantSkill() ~= nil end
-- Can this item be disenchanted by someone available, at their skill?
function C.CanDEFor(id)
  if C.CanDE(id) ~= true then return false end
  local skill = C.DisenchantSkill()
  local r = C.Item(id)
  return skill ~= nil and r and r.il and skill >= C.DESkillNeeded(r.il) or false
end

------------------------------------------------------------------ item value
-- AH net for selling `qty` units now: price after cut, minus expected lost
-- deposit (assumes ~30% of listings expire; deposit floor 1s).
function C.AHNet(id, qty)
  local mi = C.MarketItem(id)
  if not mi or not mi.m then return nil end
  local r = C.Item(id)
  -- greys go to vendors; a thin book (1-2 listings) is an asking price, not a market
  if r and r.q == 0 then return nil end
  if not C.IsGear(r) and (mi.n or 0) < 3 then return nil end
  local price
  if C.IsGear(r) then
    price = mi.m
    local wk = C.WeekMedian(id); if wk then price = math.min(price, wk) end
    -- one or two listings of a piece of gear is an asking price: haircut it
    if (mi.n or 0) < 3 then price = math.floor(price * 0.75) end
  else
    price = math.min(mi.d or mi.m, C.WeekMedian(id) or mi.d or mi.m)
  end
  local cut = price * C.settings.ahCut
  -- deposit = a share of the vendor price (Econ.lua); ~30% of listings expire once
  local dep = C.Econ and C.Econ.DepositFor(id, 1) or 0
  local risk = 0.3 * dep
  local net = price - cut - risk
  return math.floor(net), price, math.floor(cut + 0.5), math.floor(risk + 0.5)
end

-- Best route for one unit: returns route, unit value, details table.
-- Disenchanting is only a route when someone you can hand the item to can do it
-- (you, an alt, or /kina defriend). It must beat the next best route by 10% AND by
-- the trade overhead: it is a gamble on the outcome and a second sale.
function C.BestRoute(id, qty)
  local r = C.Item(id)
  local canDE = C.CanDEFor(id)
  if r and (r.bind == 1 or r.bind == 4) then
    local v = C.VendorPrice(id) or 0
    -- soulbound: only YOU can disenchant it
    local mine = C.EnchantingSkill()
    local de = mine and r.il and mine >= C.DESkillNeeded(r.il) and C.CanDE(id) == true and C.DEValue(id)
    if de and de.ev > v then return "DISENCHANT", de.ev, { de = de, vendor = v, bound = true } end
    return (v > 0) and "VENDOR" or "KEEP", v, { vendor = v, bound = true }
  end
  local vendor = C.VendorPrice(id, true) or 0
  local ah, price, cut, risk = C.AHNet(id, qty)
  local de = canDE and C.DEValue(id) or nil
  local best, route = vendor, "VENDOR"
  if ah and ah > best then best, route = ah, "AUCTION" end
  local margin = C.Econ and math.min(C.Econ.Overhead(), math.max(10, best * 0.25)) or 10
  if de and de.ev > best * 1.1 and de.ev - best >= margin then best, route = de.ev, "DISENCHANT" end
  if best <= 0 then route = "KEEP" end
  return route, best, { ah = ah, ahPrice = price, ahCut = cut, ahRisk = risk, vendor = vendor, de = de, canDE = canDE,
    deAll = (C.CanDE(id) == true) and C.DEValue(id) or nil }
end

------------------------------------------------------------------ deals
function C.EnchantingSkill()
  return C.char.prof and C.char.prof["Enchanting"] or nil
end

function C.Deals()
  local vendorDeals, deDeals = {}, {}
  local minProfit = C.settings.minDealProfit
  local skill = C.EnchantingSkill()
  for id, mi in pairs(C.market.items) do
    local r = C.Item(id)
    -- vendor flips: any listing below what a vendor pays
    local v, how = C.VendorPrice(id, true)
    if v and v > 0 and mi.l then
      local profit, units = 0, 0
      for _, step in ipairs(mi.l) do
        if step[1] < v then profit = profit + (v - step[1]) * step[2]; units = units + step[2] end
      end
      if profit >= minProfit then
        vendorDeals[#vendorDeals + 1] = { id = id, profit = profit, units = units, unit = mi.m, vendor = v, how = how }
      end
    end
    -- disenchant flips: single gear pieces below expected DE value
    if C.IsGear(r) and mi.l and C.CanDE(id) == true then
      local dv = C.DEValue(id)
      if dv and not dv.missing then
        local profit, count = 0, 0
        for _, step in ipairs(mi.l) do
          if dv.ev - step[1] >= minProfit then profit = profit + (dv.ev - step[1]) * step[2]; count = count + step[2] end
        end
        if count > 0 then
          local need = C.DESkillNeeded(r.il)
          deDeals[#deDeals + 1] = { id = id, profit = profit, count = count, unit = mi.m, ev = dv.ev,
            loss = C.DELossChance(dv, mi.m), skill = need, canNow = (skill or 0) >= need, il = r.il, q = r.q }
        end
      end
    end
  end
  table.sort(vendorDeals, function(a, b) return a.profit > b.profit end)
  -- safest first: expected profit weighted by the chance of not losing money
  table.sort(deDeals, function(a, b) return a.profit * (1 - a.loss) > b.profit * (1 - b.loss) end)
  return vendorDeals, deDeals
end
