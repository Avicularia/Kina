-- Kina: merchant offers and vendor-to-auction flips.
-- Every merchant you open is recorded (price you pay, after Bartering; stock).
-- Kina Scout's earlier merchant captures are read once at login, read-only.
local _, C = ...

local function store(id, each, packQty, packCost, stock, where, who, map, x, y)
  C.db.offers = C.db.offers or {}
  local o = C.db.offers[id]
  -- keep the cheapest known source; refresh it when re-seen
  if not o or each <= o.each or (o.where == where and o.who == who) then
    C.db.offers[id] = { each = each, pack = packQty, cost = packCost, stock = stock, where = where, who = who, t = C.Now(),
      map = map, x = x, y = y }
  end
end

local function readMerchant()
  local MF = C_MerchantFrame
  if not (MF and MF.GetItemInfo and GetMerchantNumItems) then return end
  local who = UnitName and UnitName("npc") or "?"
  local where = (GetRealZoneText and GetRealZoneText()) or "?"
  local map, px, py = C.PlayerPos() -- you are standing at the merchant
  for i = 1, GetMerchantNumItems() or 0 do
    local ok, info = pcall(MF.GetItemInfo, i)
    if ok and type(info) == "table" and info.isPurchasable ~= false and not info.hasExtendedCost
        and type(info.price) == "number" and info.price > 0 and (info.stackCount or 0) > 0 then
      local link = GetMerchantItemLink and GetMerchantItemLink(i)
      local id = C.ItemIDFromLink(link) or info.itemID
      if id then
        store(id, info.price / info.stackCount, info.stackCount, info.price,
          info.numAvailable == -1 and "unlimited" or info.numAvailable, where, who, map, px, py)
      end
    end
  end
end
C.On("MERCHANT_SHOW", readMerchant)
C.On("MERCHANT_UPDATE", readMerchant)

-- One-time read of Kina Scout's merchant captures (never written to).
local function importKinaScout()
  local ks = rawget(_G, "KinaScoutDB")
  if type(ks) ~= "table" or type(ks.contexts) ~= "table" then return end
  local n = 0
  for _, ctx in pairs(ks.contexts) do
    if type(ctx) == "table" and type(ctx.merchantOffers) == "table" then
      for id, o in pairs(ctx.merchantOffers) do
        if type(id) == "number" and type(o) == "table" and type(o.buy_unit_cp) == "number" and o.buy_unit_cp > 0 then
          local mine = C.db.offers and C.db.offers[id]
          if not mine then
            store(id, o.buy_unit_cp, o.pack_qty or 1, o.pack_cost_cp or o.buy_unit_cp, "unlimited",
              o.location or "?", "from Kina Scout"); n = n + 1
          end
        end
      end
    end
  end
  if n > 0 then C.Print(n .. " merchant prices imported from Kina Scout (read-only).") end
end
C.On("PLAYER_LOGIN", function() pcall(importKinaScout) end)

-- What it costs to BUY one from a merchant (nil if no merchant sells it).
function C.MerchantPrice(id)
  local o = C.db.offers and C.db.offers[id]
  return o and o.each, o
end

-- Vendor-to-auction flips: merchant price vs what the AH pays after the cut.
-- Needs 3+ listings so a lone overpriced listing cannot create a fake flip.
function C.VendorFlips()
  local out = {}
  for id, o in pairs(C.db.offers or {}) do
    local mi = C.MarketItem(id)
    if mi and mi.m and (mi.n or 0) >= 3 then
      local ah = math.min(mi.d or mi.m, mi.md or mi.m)
      local wk = C.WeekMedian(id); if wk then ah = math.min(ah, wk) end
      local net = ah * (1 - C.settings.ahCut) - o.each
      if net >= 5 then
        local stockN = type(o.stock) == "number" and o.stock * (o.pack or 1) or nil
        out[#out + 1] = { id = id, buy = o.each, ah = ah, net = net, margin = net / o.each, listed = mi.q, sellers = mi.n,
          stock = stockN, where = o.where, who = o.who,
          -- rough capacity: you can undercut into ~10% of what is listed
          potential = net * math.min(stockN or math.huge, math.max(1, math.floor((mi.q or 0) * 0.1))) }
      end
    end
  end
  table.sort(out, function(a, b) return a.potential > b.potential end)
  return out
end
