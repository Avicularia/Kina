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
-- 1.0.2 (Taylor: "things that can't be vendored have a vendor price somehow"): the item
-- data carries a price even for items no merchant buys. The game marks those in your
-- bags ("no value"); Kina remembers the mark and gives them no vendor price.
function C.NoteNoValue(id, noValue)
  if type(id) ~= "number" or not C.db then return end
  if type(C.db.noVend) ~= "table" then C.db.noVend = {} end
  if noValue then C.db.noVend[id] = 1 elseif C.db.noVend[id] then C.db.noVend[id] = nil end
end
function C.NoVendor(id) return C.db and type(C.db.noVend) == "table" and C.db.noVend[id] ~= nil or false end
function C.VendorPrice(id, conservative)
  if C.NoVendor(id) then return nil end
  local seen = C.db.vendor[id]
  if seen then return seen.p, "seen" end
  local r = C.Item(id)
  local v = r and r.vend
  if not v or v <= 0 then return nil end
  if conservative then return math.floor(v * (1 - C.settings.vendorMargin)), "client" end
  return v, "client"
end

-- 1.0.2 (Taylor: "when the vendor menu is opened, remove the color of all items except
-- the ones that have vendor as the highest price"): while a merchant is open, every bag
-- item that is NOT best sold to a vendor gets a grey veil; the ones to sell stay bright
-- with a small gold corner. The veils are Kina's own frames laid over the bag buttons:
-- nothing of the game's bag frames is changed. Works with the game's own bags.
-- Settings > "Grey out what not to vendor"; off in combat.
do
  local veils, used = {}, 0
  local open = false
  local function veil()
    used = used + 1
    local v = veils[used]
    if not v then
      v = CreateFrame("Frame", nil, UIParent)
      v:SetFrameStrata("HIGH")
      v.grey = v:CreateTexture(nil, "OVERLAY"); v.grey:SetAllPoints(); v.grey:SetColorTexture(0.10, 0.10, 0.11, 0.78)
      v.mark = v:CreateTexture(nil, "OVERLAY"); v.mark:SetSize(12, 12); v.mark:SetPoint("TOPLEFT", 1, -1)
      v.mark:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
      if v.EnableMouse then v:EnableMouse(false) end
      veils[used] = v
    end
    return v
  end
  local function clear() for i = 1, #veils do veils[i]:Hide() end; used = 0 end
  local function eachButton(fn)
    local function frame(f)
      if not (f and f.IsShown and f:IsShown()) then return end
      if f.EnumerateValidItems then
        for _, b in f:EnumerateValidItems() do fn(b) end
        return
      end
      local name = f.GetName and f:GetName()
      if not name then return end
      for i = 1, 40 do
        local b = _G[name .. "Item" .. i]
        if b and b.IsShown and b:IsShown() then fn(b) end
      end
    end
    frame(_G.ContainerFrameCombinedBags)
    for i = 1, 13 do frame(_G["ContainerFrame" .. i]) end
  end
  local function paint()
    clear()
    if not open or (C.settings and C.settings.vendorDim == false) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local CT = C_Container
    if not (CT and CT.GetContainerItemInfo and C.ItemCall) then return end
    eachButton(function(b)
      local bag = (b.GetBagID and b:GetBagID()) or (b.GetParent and b:GetParent() and b:GetParent().GetID and b:GetParent():GetID())
      local slot = b.GetID and b:GetID()
      if type(bag) ~= "number" or type(slot) ~= "number" then return end
      local info = CT.GetContainerItemInfo(bag, slot)
      local id = info and info.itemID
      if type(id) ~= "number" then return end
      if type(info.hasNoValue) == "boolean" and C.NoteNoValue then C.NoteNoValue(id, info.hasNoValue) end
      local sell = (not info.hasNoValue) and C.ItemCall(id) == "VENDOR"
      local v = veil()
      v:ClearAllPoints(); v:SetAllPoints(b)
      if b.GetFrameLevel and v.SetFrameLevel then v:SetFrameLevel((b:GetFrameLevel() or 1) + 6) end
      if sell then v.grey:Hide(); v.mark:Show() else v.grey:Show(); v.mark:Hide() end
      v:Show()
    end)
  end
  local queued
  local function later()
    if queued then return end
    queued = true
    C.After(0.2, function() queued = nil; local ok = pcall(paint); if not ok then clear() end end)
  end
  C.VendorDimRefresh = later
  function C.VendorDimCount() local n, sell = 0, 0; for i = 1, used do n = n + 1; if veils[i].mark:IsShown() then sell = sell + 1 end end; return n, sell end
  -- bags opened after the merchant: look again now and then while it's open
  local tk, acc = CreateFrame("Frame"), 0
  C.GuardScript(tk, "OnUpdate", "vendor veil", function(_, el)
    if not open then return end
    acc = acc + (el or 0); if acc < 1.5 then return end
    acc = 0; later()
  end)
  C.On("MERCHANT_SHOW", function() open = true; later() end)
  C.On("MERCHANT_CLOSED", function() open = false; clear() end)
  C.On("BAG_UPDATE_DELAYED", function() if open then later() end end)
  C.On("PLAYER_REGEN_DISABLED", function() if open then clear() end end)
  C.On("PLAYER_REGEN_ENABLED", function() if open then later() end end)
end
