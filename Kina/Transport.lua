-- Kina 2.1.0: two auction houses (Taylor, Nov 23: "There are two auction houses in this game
-- ... the cross faction auction house in booty bay ... I think I just discovered a MASSIVE
-- arbitrage opportunity").
--
--  * A scan made at Booty Bay (or Gadgetzan, Everlook) goes into its own price book, the
--    cross-faction one; your faction's book stays what it was.
--  * Kinas share cross-faction scans on the Kina network (TS / TQ / TZB / TZ / TZE).
--  * The two are PAIRED while both scans (yours or the network's) are under 30 minutes old:
--    Kina says "Transport tab available" and the Prices window's Transport tab opens.
--  * While the cross-faction scan is under 30 minutes old, the auction price everywhere
--    (tooltips, the widget, farms) is the better of the two houses, after each house's
--    cut. Older than that: your faction's house only, for stability.
--  * Booty Bay takes 15% (Classic's rule, until it's confirmed otherwise): Kina counts a sale
--    there 10% lower than the same sale at your faction's house.
local _, C = ...
local T = {}
C.Transport = T

T.FRESH = 30 * 60          -- a cross-faction scan counts for 30 minutes
T.EXTRA_CUT = 0.10         -- Booty Bay's extra cut over your faction's house (15% vs 5%)
T.MARGIN = 0.10            -- "buy up to" leaves 10% for the trip
T.SLOW = 1.5               -- under this many sold an hour: "sells slowly"
T.FEW = 20                 -- fewer than this cheap enough to buy: "only N worth it"
local NEUTRAL = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }

local function now() return C.Now() end
local function Net() return C.Net end
local function b36(n) return C.Share and C.Share._b36 and C.Share._b36(n) or tostring(n) end
local function n36(s, max) return C.Share and C.Share._n36 and C.Share._n36(s, max) or tonumber(s) end

------------------------------------------------------------------ where am I
function T.AtNeutral()
  for _, fn in ipairs({ GetSubZoneText, GetMinimapZoneText, GetZoneText, GetRealZoneText }) do
    if fn then local ok, z = pcall(fn); if ok and z and NEUTRAL[z] then return true end end
  end
  return false
end
C.On("AUCTION_HOUSE_SHOW", function() C.ahNeutral = T.AtNeutral() or nil end)
C.On("AUCTION_HOUSE_CLOSED", function() C.ahNeutral = nil end)

-- the names on the screen: your faction's capital, and Booty Bay
function T.HomeName()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Horde" and "Orgrimmar" or "Stormwind"
end
function T.HomeShort() return T.HomeName() == "Orgrimmar" and "OG" or "SW" end

------------------------------------------------------------------ the cross-faction book
function T.Book()
  local d = C.db
  if not d then return nil end
  d.markets = d.markets or {}
  local key = ((C.Realm and C.Realm()) or "?") .. "|Neutral"
  local m = d.markets[key]
  if type(m) ~= "table" then m = { items = {}, history = {} }; d.markets[key] = m end
  m.items = m.items or {}; m.history = m.history or {}
  return m
end
local function netStore()
  C.db.netNeutral = type(C.db.netNeutral) == "table" and C.db.netNeutral or {}
  return C.db.netNeutral
end
-- the newest cross-faction prices: your own scan or one from the network
-- returns items, time, who (nil = you), own (true when it's your scan, with listing ladders)
function T.Neutral()
  local b = T.Book()
  local items, t, who, own = b and b.items, b and b.scanTime or 0, nil, true
  for _, s in pairs(netStore()) do
    if type(s) == "table" and s.items and (s.t or 0) > t then items, t, who, own = s.items, s.t, s.name, false end
  end
  if not t or t <= 0 then return nil end
  return items, t, who, own
end
-- your faction's newest prices: your scan, your group's, or the Kina network's
function T.Home()
  local t, who = (C.market and C.market.scanTime) or 0, nil
  if C.Share and C.Share.NewestScan then local g, w = C.Share.NewestScan(); if g and g > t then t, who = g, w end end
  if C.NetPrices and C.NetPrices.Freshest then local nt = C.NetPrices.Freshest(); if nt and nt > t then t, who = nt, "the Kina network" end end
  if t <= 0 then return nil end
  return t, who
end
function T.NeutralFresh()
  local _, t = T.Neutral()
  return t and now() - t <= T.FRESH or false
end
-- paired: both houses scanned in the last 30 minutes. Returns seconds left (or nil) and
-- { homeT, homeWho, bbT, bbWho }
function T.Paired()
  local _, bt, bwho = T.Neutral()
  local ht, hwho = T.Home()
  if not (bt and ht) then return nil end
  local left = T.FRESH - (now() - math.min(bt, ht))
  if left <= 0 then return nil end
  return left, { homeT = ht, homeWho = hwho, bbT = bt, bbWho = bwho }
end
function T.NeutralItem(id)
  local items = T.Neutral()
  return items and items[id]
end

------------------------------------------------------------------ what a sale nets
-- what selling one at Booty Bay keeps, the same way C.AHNet does for your own house
local homeNet
function T.BBNet(id)
  local mi = T.NeutralItem(id)
  if not (mi and mi.m and mi.m > 0) then return nil end
  local r = C.Item and C.Item(id)
  if r and r.q == 0 then return nil end
  local gear = C.IsGear and C.IsGear(r)
  local listed = mi.n or mi.q or 0
  if not gear and listed < 3 then return nil end
  local price = gear and mi.m or (mi.d or mi.m)
  if gear and listed < 3 then price = math.floor(price * 0.75) end
  local cut = price * ((C.settings and C.settings.ahCut or 0.05) + T.EXTRA_CUT)
  local dep = C.Econ and C.Econ.DepositFor and C.Econ.DepositFor(id, 1) or 0
  local risk = 0.3 * dep
  return math.floor(price - cut - risk), price, math.floor(cut + 0.5), math.floor(risk + 0.5)
end
function T.HomeNet(id) if homeNet then return homeNet(id, 1) end end
-- C.AHNet: the better house while the cross-faction scan is fresh. A 5th value says which.
local function hook()
  if homeNet or not C.AHNet then return end
  homeNet = C.AHNet
  C.AHNet = function(id, qty)
    local net, price, cut, risk = homeNet(id, qty)
    if not T.NeutralFresh() then return net, price, cut, risk, "home" end
    local bn, bp, bc, br = T.BBNet(id)
    if bn and (not net or bn > net) then return bn, bp, bc, br, "bb" end
    return net, price, cut, risk, "home"
  end
end
hook()
function T.HouseName(h) return h == "bb" and "Booty Bay" or T.HomeName() end

------------------------------------------------------------------ the network
-- TS|time|count (I have a cross-faction scan), TQ|time|name (send it), TZB|time|parts,
-- TZ|time|packed, TZE|time|parts. Packed like the faction scans (NetPrices), 4 letters an item.
-- One scan is enough here: a stale Booty Bay price only lasts 30 minutes, and the screens
-- always say whose scan it is.
local lastSent, asked = { t = 0, at = 0 }, {}
local incoming = {}
local function enabled() return Net() and Net().Enabled() and not (C.settings and C.settings.netPricesOff) end
function T.Announce()
  if not enabled() then return end
  local b = T.Book()
  if not (b and b.scanTime and now() - b.scanTime < T.FRESH) then return end
  local n = 0
  for _, mi in pairs(b.items) do if mi.m and mi.m > 0 then n = n + 1 end end
  if n > 0 then Net().Broadcast(string.format("TS|%s|%s", b36(b.scanTime), b36(n))) end
end
local function newestHave()
  local _, t = T.Neutral()
  return t or 0
end
local function onOffer(from, f)
  if not enabled() then return end
  local t = n36(f[2])
  if not t or now() - t > T.FRESH or t > now() + 600 then return end
  if t <= newestHave() + 60 then return end
  if asked[t] and now() - asked[t] < 300 then return end
  asked[t] = now()
  Net().Broadcast("TQ|" .. b36(t) .. "|" .. ((from:match("^(%S+)") or from):lower()))
end
function T.SendScan()
  local b = T.Book()
  if not (enabled() and b and b.scanTime) then return end
  if lastSent.t == b.scanTime and now() - lastSent.at < 600 then return end
  lastSent.t, lastSent.at = b.scanTime, now()
  local rows = {}
  for id, mi in pairs(b.items) do if mi.m and mi.m > 0 then rows[#rows + 1] = { id, mi.m, mi.q or 0 } end end
  table.sort(rows, function(x, y) return x[1] < y[1] end)
  local NP = C.NetPrices
  if not (NP and NP.Codec) then return end
  local parts = NP.Codec.Pack(rows, 255 - 50)
  local tt = b36(b.scanTime)
  Net().Broadcast(string.format("TZB|%s|%s", tt, b36(#parts)))
  for _, p in ipairs(parts) do Net().BroadcastBulk("TZ|" .. tt .. "|" .. p) end
  Net().BroadcastBulk("TZE|" .. tt .. "|" .. b36(#parts))
  if C.NetNote then pcall(C.NetNote, string.format("sent your Booty Bay scan to every Kina: %d items", #rows)) end
end
local function onAsk(from, f)
  local b = T.Book()
  local t = n36(f[2])
  local me = ((UnitName and UnitName("player") or ""):match("^(%S+)") or ""):lower()
  if f[3] and f[3] ~= "" and f[3] ~= me then return end
  if b and t == b.scanTime then T.SendScan() end
end
local function onBegin(from, f)
  local t = n36(f[2])
  if not t or now() - t > T.FRESH or t <= newestHave() then return end
  incoming[from:lower()] = { t = t, rows = {} }
end
local function onPart(from, f, raw)
  local p = incoming[from:lower()]
  if not (p and n36(f[2]) == p.t) then return end
  local NP = C.NetPrices
  if NP and NP.Codec then NP.Codec.Unpack(raw:match("^TZ|[^|]*|(.*)$") or "", p.rows) end
end
local function onFinish(from, f)
  local key = from:lower()
  local p = incoming[key]
  if not (p and n36(f[2]) == p.t) then return end
  incoming[key] = nil
  local n = 0
  for _ in pairs(p.rows) do n = n + 1 end
  if n == 0 then return end
  local s = netStore()
  s[key] = { name = from, t = p.t, items = p.rows, got = now() }
  -- keep the newest 3
  local list = {}
  for k, v in pairs(s) do list[#list + 1] = { k = k, t = v.t or 0 } end
  table.sort(list, function(a, b2) return a.t > b2.t end)
  for i = 4, #list do s[list[i].k] = nil end
  if C.Prices and C.Prices.Invalidate then pcall(C.Prices.Invalidate) end
  C.Print(string.format("got Booty Bay prices from %s on the Kina network (%d items).", from, n))
  T.Check()
end
if C.After then
  C.After(0, function()
    local N = Net()
    if not N then return end
    N.On("TS", onOffer); N.On("TQ", onAsk); N.On("TZB", onBegin); N.On("TZ", onPart); N.On("TZE", onFinish)
  end)
end
-- a fresh cross-faction scan of your own: tell everyone
if C.OnMarket then C.OnMarket(function()
  local b = T.Book()
  if b and b.scanTime and now() - b.scanTime < 60 and C.After then C.After(5, T.Announce) end
  if C.After then C.After(2, function() T.Check() end) end
end) end

------------------------------------------------------------------ "Transport tab available"
local saidFor
function T.Check()
  local left, info = T.Paired()
  if not left then return end
  local key = math.min(info.homeT, info.bbT) .. ":" .. math.max(info.homeT, info.bbT)
  if saidFor == key then return end
  local first = saidFor == nil or not (C.db.transportSaid and C.db.transportSaid == key)
  saidFor = key
  if not first then return end
  C.db.transportSaid = key
  local function who(w, t) return (w and (C.Books and C.Books.Name and C.Books.Name(w) or w) or "you") .. ", " .. math.floor((now() - t) / 60) .. " min ago" end
  local sub = T.HomeName() .. ": " .. who(info.homeWho, info.homeT) .. "  ·  Booty Bay: " .. who(info.bbWho, info.bbT)
  if C.Toast and C.Toast.Notice then pcall(C.Toast.Notice, "Transport tab available", sub) end
  C.Print("|cffffc54aTransport tab available|r (/kp): " .. sub .. ". Open for 30 minutes; scanning both houses again keeps it open.")
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, function() pcall(T.Check) end) end

------------------------------------------------------------------ the numbers for the screens
local function vendorOf(id) return (C.VendorPrice and C.VendorPrice(id, true)) or 0 end
local function deOf(id)
  if not (C.CanDEFor and C.CanDEFor(id)) then return nil end
  local d = C.DEValue and C.DEValue(id)
  return d and d.ev and d.ev > 0 and math.floor(d.ev) or nil
end
-- how fast it sells at a house (per hour), when Kina has watched it there
local function soldPerHour(id, bb)
  local m = bb and T.Book() or C.market
  local v = m and m.vel and m.vel[id]
  if v and (v.n or 0) >= 2 then return v.v end
  return nil
end
T.SoldPerHour = soldPerHour
-- the listing ladder at a house (your own scans only)
local function ladder(id, bb)
  local m = bb and T.Book() or C.market
  if bb then local _, _, _, own = T.Neutral(); if not own then return nil end end
  local mi = m and m.items and m.items[id]
  return mi and mi.l
end
-- how many are listed at or under a price, and the steps: "3 @ 1s 30c · 15 @ 1s 44c"
function T.Depth(id, bb, upTo)
  local L = ladder(id, bb)
  if not L then return nil end
  local n, steps = 0, {}
  for _, st in ipairs(L) do
    if st[1] <= upTo then n = n + (st[2] or 1); steps[#steps + 1] = (st[2] or 1) .. " @ " .. C.Money(math.floor(st[1])) end
  end
  return n, steps
end

-- one item, both houses: listed lows, what each nets, vendor, disenchant, and the carry
function T.Item(id)
  local a = C.MarketItem and C.MarketItem(id)
  local b = T.NeutralItem(id)
  local x = { id = id, homeLow = a and a.m, bbLow = b and b.m, vendor = vendorOf(id), de = deOf(id) }
  x.homeNet = T.HomeNet(id)
  x.bbNet = T.BBNet(id)
  -- the carry: buy at the cheap house, sell at the other; "buy up to" leaves 10% for the trip
  if x.homeLow and x.bbNet then
    local upTo = math.floor(x.bbNet * (1 - T.MARGIN))
    if x.homeLow < upTo then x.carry = { from = "home", to = "bb", upTo = upTo, sell = x.bbLow, net = x.bbNet } end
  end
  if not x.carry and x.bbLow and x.homeNet then
    local upTo = math.floor(x.homeNet * (1 - T.MARGIN))
    if x.bbLow < upTo then x.carry = { from = "bb", to = "home", upTo = upTo, sell = x.homeLow, net = x.homeNet } end
  end
  if x.carry then
    local c = x.carry
    c.sold = soldPerHour(id, c.to == "bb")
    c.slow = c.sold ~= nil and c.sold < T.SLOW
    c.depth, c.steps = T.Depth(id, c.from == "bb", c.upTo)
    c.few = c.depth ~= nil and c.depth < T.FEW
    local buyAt = (c.from == "bb") and x.bbLow or x.homeLow
    c.each = c.net - buyAt
    c.profit = c.each * math.min(c.depth or 20, 20)
  end
  return x
end
function T.Short(h) return h == "bb" and "BB" or T.HomeShort() end

-- every item worth carrying right now (sorted by profit): { carry = {...}, slow = {...} }
function T.CarryList()
  local items = T.Neutral()
  local carry, slow = {}, {}
  if not items then return carry, slow end
  local seen = {}
  local function consider(id)
    if seen[id] then return end
    seen[id] = true
    local r = C.Item and C.Item(id)
    if r and (r.q == 0 or r.bind == 1 or r.bind == 4) then return end
    local x = T.Item(id)
    if x.carry then
      x.name = (r and r.name) or ("item " .. id)
      if x.carry.slow then slow[#slow + 1] = x else carry[#carry + 1] = x end
    end
  end
  for id in pairs(items) do consider(id) end
  for id in pairs((C.market and C.market.items) or {}) do if items[id] then consider(id) end end
  table.sort(carry, function(p, q) return (p.carry.profit or 0) > (q.carry.profit or 0) end)
  table.sort(slow, function(p, q) return (p.carry.profit or 0) > (q.carry.profit or 0) end)
  return carry, slow
end

------------------------------------------------------------------ your bags
-- every unbound item in your bags: { id, count, name, x = T.Item }
function T.BagItems()
  local counts = C.NetWorth and C.NetWorth.Count and C.NetWorth.Count(C.PlayerBags()) or {}
  local out = {}
  for id, n in pairs(counts) do
    local r = C.Item and C.Item(id)
    if not (r and (r.bind == 1 or r.bind == 4)) then
      out[#out + 1] = { id = id, count = n, name = (r and r.name) or ("item " .. id), x = T.Item(id) }
    end
  end
  table.sort(out, function(p, q) return p.name < q.name end)
  return out
end
-- the winner for one bag item in a view: "home", "bb", "vendor", "de" and its value
-- mode 1 = your faction's house, 2 = Booty Bay, 3 = both
function T.Winner(x, mode)
  local best, what = 0, nil
  local function try(k, v) if v and v > best then best, what = v, k end end
  if mode ~= 2 then try("home", x.homeNet) end
  if mode ~= 1 then try("bb", x.bbNet) end
  try("vendor", x.vendor)
  try("de", x.de)
  return what, best
end

------------------------------------------------------------------ selling at the auction house
-- 2.1.0 (Taylor: "Sell to Alliance (only works at a stormwind auctioneer) that posts the
-- next item like ForeverForge does ... The posting price is the same price as whatever the
-- lowest posting price currently is, updated in real time"): Post next asks the auction house
-- for the item's lowest price right now, and posts at exactly that. Every post is a click of
-- yours (the game requires it). A price that would sell for less than the vendor or
-- disenchant value is never posted.
local AH = C_AuctionHouse
T.post = { live = {}, waiting = nil, pending = nil, status = nil }
function T.SellingOn() return not (C.settings and C.settings.ahSellOff) end
function T.Duration() local d = C.settings and tonumber(C.settings.postDur); return (d == 1 or d == 3) and d or 2 end
function T.DurationText(d) return ({ "2 hours", "8 hours", "24 hours" })[d or T.Duration()] end
-- can I sell to this house here?
function T.CanSellTo(house)
  if not C.ahOpen then return false, "open the auction house first" end
  if house == "bb" and not C.ahNeutral then return false, "only at the Booty Bay auctioneer" end
  if house == "home" and C.ahNeutral then return false, "only at the " .. T.HomeName() .. " auctioneer" end
  if not (AH and AH.PostItem) then return false, "this game client can't post from addons" end
  return true
end
local function keyOf(id)
  if AH and AH.MakeItemKey then local ok, k = pcall(AH.MakeItemKey, id); if ok then return k end end
  return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end
local function isCommodity(id)
  local ok, info = pcall(AH.GetItemKeyInfo, keyOf(id))
  return ok and info and info.isCommodity or false
end
-- ask the auction house for the item's listings now
function T.Ask(id)
  if not (AH and AH.SendSearchQuery) then return false end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then return false end
  local sorts = { { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0, reverseSort = false } }
  local ok = pcall(AH.SendSearchQuery, keyOf(id), sorts, true)
  if ok then T.post.waiting = { id = id, at = GetTime and GetTime() or 0 } end
  return ok
end
local function gotPrice(id, unit, none)
  T.post.live[id] = { unit = unit, none = none, at = GetTime and GetTime() or 0 }
  if T.post.waiting and T.post.waiting.id == id then T.post.waiting = nil end
  if T.OnChange then pcall(T.OnChange) end
end
C.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, id)
  if not (AH and AH.GetCommoditySearchResultInfo and id) then return end
  local r = AH.GetCommoditySearchResultInfo(id, 1)
  gotPrice(id, r and r.unitPrice, not r)
end)
C.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, key)
  local id = type(key) == "table" and key.itemID
  if not (id and AH and AH.GetNumItemSearchResults) then return end
  local best
  for i = 1, AH.GetNumItemSearchResults(key) or 0 do
    local r = AH.GetItemSearchResultInfo(key, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and (not r.itemKey or (r.itemKey.itemSuffix or 0) == 0) then
      local q = math.max(1, r.quantity or 1)
      local u = r.buyoutAmount / q
      if not best or u < best then best = u end
    end
  end
  gotPrice(id, best and math.floor(best + 0.5), not best)
end)
-- the first bag slot holding it
local function slotOf(id)
  local CT = C_Container
  for _, bag in ipairs(C.PlayerBags()) do
    for slot = 1, (CT and CT.GetContainerNumSlots and CT.GetContainerNumSlots(bag)) or 0 do
      local info = CT.GetContainerItemInfo(bag, slot)
      if info and info.itemID == id and not info.isLocked then return bag, slot end
    end
  end
end
-- the lowest price a sale may go at: never under what the vendor or disenchanting pays
function T.Floor(x, house)
  local cut = (C.settings and C.settings.ahCut or 0.05) + (house == "bb" and T.EXTRA_CUT or 0)
  local keep = math.max(x.vendor or 0, x.de or 0)
  return keep > 0 and math.ceil(keep / (1 - cut)) or 0
end
-- post one: returns "posted", "asked", "confirm", "wont", or nil and why
function T.Post(row, house, qty)
  local ok, why = T.CanSellTo(house)
  if not ok then return nil, why end
  local p = T.post
  -- a post the server wanted confirmed goes first
  if p.pending then
    local q = p.pending; p.pending = nil
    if q.commodity then pcall(AH.ConfirmPostCommodity, q.loc, q.dur, q.qty, q.unit) else pcall(AH.ConfirmPostItem, q.loc, q.dur, q.qty, nil, q.unit) end
    p.sent = { id = q.id, at = GetTime and GetTime() or 0 }
    return "posted", q
  end
  local id = row.id
  local live = p.live[id]
  local fresh = live and (GetTime and GetTime() or 0) - live.at < 20
  if not fresh then
    if T.Ask(id) then return "asked" end
    return nil, "the auction house is busy: click again in a moment"
  end
  local unit = live.unit
  if live.none or not unit then
    -- nobody lists it: the last scan's lowest at this house, if there is one
    unit = (house == "bb") and row.x.bbLow or row.x.homeLow
    if not unit then return "wont", "nobody lists it here and Kina has no price for it" end
  end
  local floor = T.Floor(row.x, house)
  if unit < floor then
    return "wont", string.format("the lowest listing (%s) sells for less than %s", C.Money(unit),
      (row.x.de or 0) > (row.x.vendor or 0) and "disenchanting it" or "a vendor pays")
  end
  local bag, slot = slotOf(id)
  if not bag then return nil, "it isn't in your bags any more" end
  local loc = ItemLocation and ItemLocation.CreateFromBagAndSlot and ItemLocation:CreateFromBagAndSlot(bag, slot)
  if not loc then return nil, "this game client can't post from addons" end
  local commodity = isCommodity(id)
  local have = (AH.GetAvailablePostCount and AH.GetAvailablePostCount(loc)) or row.count
  qty = math.max(1, math.min(tonumber(qty) or have, have))
  if not commodity and unit < 100 then unit = 100 end -- (the game refuses non-stacking items under 1s)
  local dur = T.Duration()
  local okp, needs
  if commodity then okp, needs = pcall(AH.PostCommodity, loc, dur, qty, unit)
  else okp, needs = pcall(AH.PostItem, loc, dur, qty, nil, unit) end
  if not okp then return nil, "the game refused the post (" .. tostring(needs) .. ")" end
  if needs then
    p.pending = { id = id, loc = loc, dur = dur, qty = qty, unit = unit, commodity = commodity }
    return "confirm", { unit = unit, qty = qty }
  end
  p.sent = { id = id, at = GetTime and GetTime() or 0 }
  return "posted", { unit = unit, qty = qty }
end
C.On("AUCTION_HOUSE_AUCTION_CREATED", function()
  if T.post.sent and T.OnPosted then pcall(T.OnPosted, T.post.sent.id) end
  T.post.sent = nil
end)
C.On("AUCTION_HOUSE_CLOSED", function() T.post.pending, T.post.waiting = nil, nil end)
-- ForeverForge Auction posts through the same window: the two can't both do it
function T.Conflict()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverForge_Auction"))
    or (IsAddOnLoaded and IsAddOnLoaded("ForeverForge_Auction"))
  return loaded and "ForeverForge Auction" or nil
end
