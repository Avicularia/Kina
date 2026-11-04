-- Kina: what a vendor REALLY pays.
-- Forever's server pays less than the client's item data for some items, and
-- patches cut crafted-item vendor prices. Each time you sell to a merchant, the
-- buyback list shows the real price; Kina learns it for every character.
local _, C = ...

local function learn()
  if not GetNumBuybackItems then return end
  local now = C.Now()
  for i = 1, GetNumBuybackItems() or 0 do
    local _, _, price, qty = GetBuybackItemInfo(i)
    local link = GetBuybackItemLink and GetBuybackItemLink(i)
    local id = C.ItemIDFromLink(link)
    if id and price and qty and qty > 0 then
      local each = math.floor(price / qty + 0.5)
      local r = C.Item(id)
      local client = r and r.vend
      -- learn what the merchant really paid, lower prices too (a server cut and a
      -- damaged item look the same; the lower one is the safe one to plan with)
      local damaged = C.IsGear(r) and client and each < client or nil
      C.db.vendor[id] = { p = each, t = now, c = client, maybeDamaged = damaged }
    end
  end
end
C.On("MERCHANT_SHOW", learn)
C.On("MERCHANT_UPDATE", learn)

-- Vendor price for one unit and how we know it: "seen", "client" or nil.
-- conservative=true applies the safety margin to unlearned prices.
function C.VendorPrice(id, conservative)
  local seen = C.db.vendor[id]
  if seen then return seen.p, "seen" end
  local r = C.Item(id)
  local v = r and r.vend
  if not v or v <= 0 then return nil end
  if conservative then return math.floor(v * (1 - C.settings.vendorMargin)), "client" end
  return v, "client"
end
