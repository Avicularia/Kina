-- Kina: trade ledger.
-- * AH sales, purchases and expiries are read from auction mail invoices.
-- * Mail sent to your OWN characters is a transfer, not income: the sender is
--   credited with the value it produced (so the Rogue keeps credit for greens it
--   mails to an enchanter alt), and the account total never counts it twice.
-- Uses only mail and money events Kina Scout has proven safe on Forever.
local _, C = ...
local MAIL_DAYS = 30

local function L()
  C.db.ledger = C.db.ledger or { seen = {}, entries = {}, transfers = {} }
  return C.db.ledger
end

-- name -> itemID from everything we know (scan cache, bags)
local nameIndex, nameIndexSize
local function idByName(name)
  if not name then return nil end
  local n = 0; for _ in pairs(C.db.items) do n = n + 1 end
  if not nameIndex or n ~= nameIndexSize then
    nameIndex, nameIndexSize = {}, n
    for id, r in pairs(C.db.items) do if r.name then nameIndex[r.name] = id end end
  end
  return nameIndex[name]
end
C.ItemIDByName = idByName

local function ownCharacter(name)
  if not name or name == "" then return nil end
  local short = name:match("^([^%-]+)") or name
  for key in pairs(C.db.chars) do
    if key:match("^([^%-]+)"):lower() == short:lower() then return key end
  end
end

------------------------------------------------------------------ inbox
local function scanInbox()
  if not (GetNumInboxItems and GetInboxHeaderInfo) then return end
  local led, now = L(), C.Now()
  led.seenN = led.seenN or {}
  local present = {} -- identical mails in this inbox: each one is its own sale
  local sold = (AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s"):gsub("%%s", "")
  local won = (AUCTION_WON_MAIL_SUBJECT or "Auction won: %s"):gsub("%%s", "")
  for i = 1, GetNumInboxItems() do
    local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    if subject and daysLeft then
      -- arrival estimate is stable across visits, so each mail is recorded once
      local arrived = math.floor((now - (MAIL_DAYS - daysLeft) * 86400) / 300)
      local key = tostring(sender) .. "|" .. subject .. "|" .. tostring(money) .. "|" .. arrived
      present[key] = (present[key] or 0) + 1
      local have = led.seenN[key] or (led.seen[key] and 1 or 0)
      if have < present[key] then
        local invType, itemName, buyer, bid, buyout, deposit, cut, _, _, count = nil
        if GetInboxInvoiceInfo then invType, itemName, buyer, bid, buyout, deposit, cut, _, _, count = GetInboxInvoiceInfo(i) end
        -- an auction mail whose invoice hasn't loaded yet: leave it for the next update
        local isAH = subject:find(sold, 1, true) or subject:find(won, 1, true)
        local wait = isAH and not invType
        local e
        if invType == "seller" then
          count = count or tonumber(subject:match("%((%d+)%)")) or 1
          e = { kind = "sale", item = itemName, id = idByName(itemName), qty = count,
            gross = (buyout and buyout > 0) and buyout or bid, cut = cut, deposit = deposit, net = money, who = buyer }
        elseif invType == "buyer" then
          count = count or tonumber(subject:match("%((%d+)%)")) or 1
          e = { kind = "buy", item = itemName, id = idByName(itemName), qty = count, cost = (buyout and buyout > 0) and buyout or bid }
        elseif subject:find(((AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"):gsub("%%s", "")), 1, true) then
          local name = subject:match(":%s*(.+)$")
          e = { kind = "expired", item = name, id = idByName(name) }
        elseif ownCharacter(sender) and ownCharacter(sender) ~= C.charKey then
          e = { kind = "received", from = ownCharacter(sender), money = money }
        end
        if e and not wait then
          e.t = now; e.char = C.charKey
          if C.LedgerFromMail then pcall(C.LedgerFromMail, e) end
          if e.kind == "sale" and C.OnFarmItemSold then pcall(C.OnFarmItemSold, e) end
          table.insert(led.entries, e)
          while #led.entries > 3000 do table.remove(led.entries, 1) end
        end
        if not wait then led.seen[key] = now; led.seenN[key] = have + 1 end
      end
    end
  end
  -- forget dedupe keys older than the mail lifetime
  for k, t in pairs(led.seen) do if now - t > (MAIL_DAYS + 1) * 86400 then led.seen[k] = nil; led.seenN[k] = nil end end
end
C.On("MAIL_INBOX_UPDATE", function() pcall(scanInbox) end)

------------------------------------------------------------------ outgoing transfers
-- While the mail window is open, remember what is attached and to whom; when the
-- postage is charged (a money drop), the mail was sent.
local mailOpen, pending = false, nil
local watcher = CreateFrame("Frame")
watcher:Hide()
local acc = 0
watcher:SetScript("OnUpdate", function(_, el)
  acc = acc + el; if acc < 0.3 then return end; acc = 0
  if not mailOpen or not GetSendMailItem then return end
  local to = SendMailNameEditBox and SendMailNameEditBox:GetText()
  local items, n = {}, 0
  for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
    local name, itemID, _, count = GetSendMailItem(i)
    if name then
      itemID = itemID or idByName(name)
      if itemID then items[itemID] = (items[itemID] or 0) + (count or 1); n = n + 1 end
    end
  end
  local money = GetSendMailMoney and GetSendMailMoney() or 0
  if n > 0 or money > 0 then pending = { to = to, items = items, n = n, money = money, money0 = GetMoney() }
  elseif pending and GetMoney() >= pending.money0 then
    -- attachments cleared without postage: not sent (cancelled)
    pending = nil
  end
end)
C.On("MAIL_SHOW", function() mailOpen = true; watcher:Show() end)
C.On("MAIL_CLOSED", function() mailOpen = false; watcher:Hide(); pending = nil end)
C.On("PLAYER_MONEY", function()
  if not (mailOpen and pending) then return end
  local spent = pending.money0 - GetMoney()
  if spent <= 0 then return end
  local p = pending; pending = nil
  local toChar = ownCharacter(p.to)
  if not toChar or toChar == C.charKey then return end
  local value = 0
  for id, n in pairs(p.items) do value = value + (select(2, C.BestRoute(id, n)) or 0) * n end
  table.insert(L().transfers, { t = C.Now(), from = C.charKey, to = toChar, items = p.items, value = value, money = p.money })
  C.Print(string.format("transfer to %s recorded: %s of items (credited to %s).", toChar, C.Money(value), C.charKey))
end)

------------------------------------------------------------------ reports
-- Per item: units sold, net received, units bought, cost, realized profit.
-- Items you never bought (farmed) carry no cost; bought items use average cost.
function C.LedgerItems(days)
  local cutoff = days and (C.Now() - days * 86400) or 0
  local by = {}
  for _, e in ipairs(L().entries) do
    if e.t >= cutoff and (e.kind == "sale" or e.kind == "buy" or e.kind == "expired") then
      local key = e.id or e.item or "?"
      local r = by[key]
      if not r then r = { id = e.id, item = e.item, sold = 0, net = 0, bought = 0, cost = 0, expired = 0, last = 0 }; by[key] = r end
      if e.kind == "sale" then r.sold = r.sold + (e.qty or 1); r.net = r.net + (e.net or 0)
      elseif e.kind == "buy" then r.bought = r.bought + (e.qty or 1); r.cost = r.cost + (e.cost or 0)
      else r.expired = r.expired + 1 end
      r.last = math.max(r.last, e.t)
    end
  end
  local out = {}
  for _, r in pairs(by) do
    local avg = r.bought > 0 and (r.cost / r.bought) or 0
    r.profit = r.net - avg * math.min(r.sold, r.bought > 0 and r.sold or 0)
    r.sellThrough = (r.sold + r.expired > 0) and r.sold / (r.sold + r.expired) or nil
    out[#out + 1] = r
  end
  table.sort(out, function(a, b) return a.last > b.last end)
  return out
end

-- Per character: AH net, AH spend, value sent to / received from your alts.
function C.LedgerByCharacter(days)
  local cutoff = days and (C.Now() - days * 86400) or 0
  local by = {}
  local function row(k) by[k] = by[k] or { char = k, net = 0, spent = 0, sent = 0, received = 0 }; return by[k] end
  for _, e in ipairs(L().entries) do
    if e.t >= cutoff then
      if e.kind == "sale" then row(e.char).net = row(e.char).net + (e.net or 0)
      elseif e.kind == "buy" then row(e.char).spent = row(e.char).spent + (e.cost or 0) end
    end
  end
  for _, tr in ipairs(L().transfers) do
    if tr.t >= cutoff then
      row(tr.from).sent = row(tr.from).sent + tr.value
      row(tr.to).received = row(tr.to).received + tr.value
    end
  end
  local out = {}
  for _, r in pairs(by) do
    -- production = what this character earned plus what it handed to alts
    r.produced = r.net - r.spent + r.sent - r.received
    out[#out + 1] = r
  end
  table.sort(out, function(a, b) return a.produced > b.produced end)
  return out
end

------------------------------------------------------------------ trade log
-- Every trade as it happens, kept 5000 trades:
--   AH buys and posts   hooked when you (or ForeverForge's sniper) click Buy / Post;
--                       the price is the gold that actually left your bags
--   AH sales, expiries  from the auction mail (and buys again, if the click was missed)
--   vendor sales/buys   bag + gold changes while a merchant is open
--   disenchants         which item went in and what came out
local function T()
  local led = L(); led.trades = led.trades or {}; return led.trades
end
local function addTrade(e)
  e.t = e.t or C.Now(); e.char = e.char or C.charKey
  local list = T(); list[#list + 1] = e
  while #list > 5000 do table.remove(list, 1) end
  if C.OnLedger then pcall(C.OnLedger) end
  return e
end

-- Crafting: "You create: [Rough Dynamite]x2." The recipe's reagents were used up, so
-- their cost moves onto what you made (a flip of the mats ends here, the crafted item
-- carries their cost until it sells).
local function pat(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. p .. "$"
end
local CREATE
local outIndex
local function recipeFor(id)
  if not outIndex then
    outIndex = {}
    for spell, r in pairs(C.RecipeCatalog and C.RecipeCatalog() or {}) do
      if r.out and r.reagents then
        local cur = outIndex[r.out]
        -- prefer a recipe you know
        if not cur or (C.IsKnown and C.IsKnown(spell) and not (C.IsKnown(cur.spell))) then outIndex[r.out] = r end
      end
    end
  end
  return outIndex[id]
end
C.On("CHAT_MSG_LOOT", function(_, text)
  if type(text) ~= "string" then return end
  CREATE = CREATE or { { pat(LOOT_ITEM_CREATED_SELF_MULTIPLE or "You create: %sx%d."), true }, { pat(LOOT_ITEM_CREATED_SELF or "You create: %s.") } }
  for _, p in ipairs(CREATE) do
    local link, n = p[1] and text:match(p[1])
    if link then
      local id = C.ItemIDFromLink(link)
      n = p[2] and tonumber(n) or 1
      local r = id and recipeFor(id)
      if r then
        local crafts = math.max(1, math.floor(n / (r.n or 1) + 0.5))
        local used = {}
        for mat, q in pairs(r.reagents) do used[mat] = q * crafts end
        addTrade({ kind = "craft", id = id, qty = n, used = used })
      end
      return
    end
  end
end)
C.AddTrade = addTrade
function C.Trades() return T() end

local function snap()
  local s = {}
  for id, e in pairs(C.BagItems and C.BagItems() or {}) do s[id] = e.count end
  return s
end
local function itemFromLocation(loc)
  if not (loc and C_Item and C_Item.GetItemID) then return nil end
  local ok, id = pcall(C_Item.GetItemID, loc)
  return ok and id or nil
end

-- AH: what was clicked, matched to the gold that left (oldest first)
local ahOpen, pending, lastKey, lastKeyAt = false, {}, nil, nil
local function hook(name, fn)
  if hooksecurefunc and C_AuctionHouse and type(C_AuctionHouse[name]) == "function" then
    pcall(hooksecurefunc, C_AuctionHouse, name, fn)
  end
end
local function now() return GetTime and GetTime() or 0 end
local function remember(itemKey) if type(itemKey) == "table" and itemKey.itemID then lastKey, lastKeyAt = itemKey.itemID, now() end end
hook("SendSearchQuery", remember)
hook("SendSellSearchQuery", remember)
-- Which item a single-listing buy is: ask the auction house about that listing;
-- only if it won't say, use the item you searched for in the last minute. The
-- purchase mail corrects it either way (C.LedgerFromMail).
hook("PlaceBid", function(auctionID, amount)
  local id, guess
  local AH = C_AuctionHouse
  if AH and AH.GetAuctionInfoByID then
    local ok, info = pcall(AH.GetAuctionInfoByID, auctionID)
    if ok and type(info) == "table" then
      id = (type(info.itemKey) == "table" and info.itemKey.itemID) or (info.itemLink and C.ItemIDFromLink(info.itemLink)) or nil
    end
  end
  if not id and lastKeyAt and now() - lastKeyAt < 60 then id, guess = lastKey, true end
  pending[#pending + 1] = { kind = "ahbuy", id = id, guess = guess, qty = 1, amount = amount, at = now() }
end)
hook("ConfirmCommoditiesPurchase", function(itemID, qty)
  pending[#pending + 1] = { kind = "ahbuy", id = itemID, qty = qty or 1, at = now() }
end)
hook("PostItem", function(loc, duration, qty, bid, buyout)
  pending[#pending + 1] = { kind = "post", id = itemFromLocation(loc), qty = qty or 1, each = buyout and buyout > 0 and buyout / math.max(1, qty or 1) or bid, duration = duration, at = now() }
end)
hook("PostCommodity", function(loc, duration, qty, unitPrice)
  pending[#pending + 1] = { kind = "post", id = itemFromLocation(loc), qty = qty or 1, each = unitPrice, duration = duration, at = now() }
end)
local ahMoney
C.On("AUCTION_HOUSE_SHOW", function() ahOpen = true; ahMoney = GetMoney(); pending = {} end)
C.On("AUCTION_HOUSE_CLOSED", function() ahOpen = false; pending = {} end)

-- vendor: bag + gold changes while a merchant window is open
local merchant, vBags, vMoney, vQueued = false, nil, nil, false
local vWait = 0
local function vendorCheck()
  vQueued = false
  if not merchant or not vBags then return end
  local nowBags, money = snap(), GetMoney()
  local delta = money - vMoney
  -- the game can update your bags a moment before your gold (or the other way
  -- round): wait for both before deciding, or the sale is never recorded
  do
    local lostAny, gainedAny = false, false
    for id, n in pairs(vBags) do if n > (nowBags[id] or 0) then lostAny = true; break end end
    for id, n in pairs(nowBags) do if n > (vBags[id] or 0) then gainedAny = true; break end end
    local half = (lostAny and delta == 0) or (delta > 0 and not lostAny) or (delta < 0 and not gainedAny) or (gainedAny and delta == 0)
    if half and vWait < 6 then vWait = vWait + 1; C.After(0.5, vendorCheck); return end
    vWait = 0
  end
  local lost, gained, lostValue, gainedValue = {}, {}, 0, 0
  for id, n in pairs(vBags) do
    local d = n - (nowBags[id] or 0)
    if d > 0 then lost[id] = d; lostValue = lostValue + d * math.max(1, (C.Item(id) or {}).vend or 1) end
  end
  for id, n in pairs(nowBags) do
    local d = n - (vBags[id] or 0)
    if d > 0 then gained[id] = d; gainedValue = gainedValue + d * math.max(1, (C.Item(id) or {}).vend or 1) end
  end
  if delta > 0 and next(lost) then
    for id, d in pairs(lost) do
      local share = math.floor(delta * d * math.max(1, (C.Item(id) or {}).vend or 1) / lostValue + 0.5)
      addTrade({ kind = "vendorsale", id = id, qty = d, total = share, each = share / d })
    end
  elseif delta < 0 and next(gained) then
    for id, d in pairs(gained) do
      local share = math.floor(-delta * d * math.max(1, (C.Item(id) or {}).vend or 1) / gainedValue + 0.5)
      addTrade({ kind = "vendorbuy", id = id, qty = d, total = -share, each = share / d })
    end
  end
  vBags, vMoney = nowBags, money
end
local function vendorQueue() if merchant and not vQueued then vQueued = true; C.After(0.6, vendorCheck) end end
C.On("MERCHANT_SHOW", function() merchant = true; vBags = snap(); vMoney = GetMoney() end)
C.On("MERCHANT_CLOSED", function() merchant = false; vBags = nil end)
C.On("BAG_UPDATE_DELAYED", vendorQueue)

-- gold changes: AH clicks are confirmed here
C.On("PLAYER_MONEY", function()
  vendorQueue()
  if not ahOpen then return end
  local money = GetMoney()
  local delta = money - (ahMoney or money)
  ahMoney = money
  if delta >= 0 then return end
  local t = now()
  while pending[1] and t - pending[1].at > 30 do table.remove(pending, 1) end -- never went through
  if not pending[1] then return end
  local pick = 1
  for i, p in ipairs(pending) do if p.amount and p.amount == -delta then pick = i; break end end
  local p = table.remove(pending, pick)
  if p.kind == "post" then
    addTrade({ kind = "post", id = p.id, qty = p.qty, each = p.each, deposit = -delta, total = delta,
      hours = ({ 2, 8, 24 })[p.duration or 1] })
    if C.SessionPosted then C.SessionPosted(p.id, p.qty or 1) end -- listed during a farm: still yours
  else
    addTrade({ kind = "ahbuy", id = p.id, guess = p.guess, qty = p.qty, total = delta, each = -delta / math.max(1, p.qty) })
  end
end)

-- mail: AH sales and expiries; a buy only if the click wasn't already recorded
function C.LedgerFromMail(e)
  if e.kind == "sale" then
    addTrade({ kind = "ahsale", id = e.id, item = e.item, qty = e.qty, total = e.net or 0, each = (e.net or 0) / math.max(1, e.qty or 1),
      gross = e.gross, cut = e.cut, deposit = e.deposit, who = e.who })
    if C.SessionPosted then C.SessionPosted(e.id, -(e.qty or 1)) end
  elseif e.kind == "expired" then
    addTrade({ kind = "expired", id = e.id, item = e.item, qty = 1, total = 0 })
    if C.SessionPosted then C.SessionPosted(e.id, -1e9) end
  elseif e.kind == "buy" then
    local list = T()
    -- the mail names the real item: match the click by price (same item first,
    -- then a click Kina put on the wrong item, which it now corrects)
    for pass = 1, 2 do
      for i = #list, math.max(1, #list - 400), -1 do
        local x = list[i]
        if x.kind == "ahbuy" and not x.mailed and math.abs((x.total or 0) + (e.cost or 0)) <= 1
          and ((pass == 1 and (x.id == nil or x.id == e.id)) or (pass == 2 and e.id and x.id ~= e.id)) then
          x.mailed = true
          if x.id ~= e.id then x.id, x.item, x.fixed = e.id, e.item, true end
          -- the invoice's count is the real one (the click may have guessed 1)
          if e.qty and e.qty ~= x.qty then x.qty = e.qty end
          x.each = -(x.total or 0) / math.max(1, x.qty or 1)
          return
        end
      end
    end
    addTrade({ kind = "ahbuy", id = e.id, item = e.item, qty = e.qty or 1, total = -(e.cost or 0), each = (e.cost or 0) / math.max(1, e.qty or 1), mailed = true, late = true })
  end
end

-- One-time repair (0.11.0): AH buys Kina put on the wrong item (it guessed from
-- your last search) and the purchase mail then logged again under the right one.
C.On("INIT", function()
  if C.db.ledgerFix0110 then return end
  C.db.ledgerFix0110 = true
  local list, drop, fixed = T(), {}, 0
  for i, late in ipairs(list) do
    if late.kind == "ahbuy" and late.late and late.id then
      for j = i - 1, math.max(1, i - 400), -1 do
        local x = list[j]
        if x.kind == "ahbuy" and not x.mailed and x.id ~= late.id and math.abs((x.total or 0) - (late.total or 0)) <= 1 and late.t - x.t < 7 * 86400 then
          x.id, x.item, x.qty, x.mailed, x.fixed = late.id, late.item, late.qty or x.qty, true, true
          x.each = -(x.total or 0) / math.max(1, x.qty or 1)
          drop[i] = true; fixed = fixed + 1
          break
        end
      end
    end
  end
  for i = #list, 1, -1 do if drop[i] then table.remove(list, i) end end
  if fixed > 0 then C.Print(string.format("ledger: corrected %d auction buy%s that were logged under the wrong item.", fixed, fixed == 1 and "" or "s")) end
end)

-- "Fix held items" (Ledger tab): flips the ledger says you still hold but that are
-- no longer in your bags, bank or AH listings were almost always sold to a vendor
-- while Kina missed it. Lists them and asks before marking them sold at vendor price.
local function outstandingPosts(id)
  local cut, posted, gone = C.Now() - 2 * 86400, 0, 0
  for _, e in ipairs(T()) do
    if e.id == id and e.t >= cut then
      if e.kind == "post" then posted = posted + (e.qty or 1)
      elseif e.kind == "ahsale" then gone = gone + (e.qty or 1)
      elseif e.kind == "expired" then gone = gone + (e.qty or 1) end
    end
  end
  return math.max(0, posted - gone)
end
function C.LedgerFixHeld()
  local have = C.Holdings and C.Holdings(true) or {}
  local list, lines = {}, {}
  for _, r in ipairs(C.LedgerFlips()) do
    if r.left > 0 and r.id then
      local missing = r.left - (have[r.id] or 0) - outstandingPosts(r.id)
      if missing > 0 then
        local v = C.VendorPrice and C.VendorPrice(r.id, true) or 0
        list[#list + 1] = { id = r.id, n = missing, v = v }
        if #lines < 12 then lines[#lines + 1] = string.format("%d x %s (%s)", missing, (C.Item(r.id) or {}).name or ("item " .. r.id), C.Money(v * missing)) end
      end
    end
  end
  if #list == 0 then C.Print("ledger: every held item is still in your bags, bank or on the AH. Nothing to fix."); return end
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs.KINA_FIXHELD = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, data)
      for _, x in ipairs(data) do
        addTrade({ kind = "vendorsale", id = x.id, qty = x.n, total = x.v * x.n, each = x.v, assumed = true })
      end
      C.Print(string.format("ledger: marked %d item type%s as sold to a vendor.", #data, #data == 1 and "" or "s"))
      if C.Refresh then C.Refresh() end
    end,
  }
  C.ShowPopup("KINA_FIXHELD", "Kina: these are no longer in your bags, bank or AH listings. Mark them as sold to a vendor (at vendor price)?\n\n"
    .. table.concat(lines, "\n") .. ((#list > #lines) and ("\n... and " .. (#list - #lines) .. " more") or "")
    .. "\n\n(Items still in your mailbox would be counted too: collect your mail first.)", nil, list)
end

-- disenchants: called by the loot reader for loot whose source is an item
local deOpen, deSnap = {}, nil
local spells = CreateFrame("Frame")
if spells.RegisterUnitEvent then pcall(spells.RegisterUnitEvent, spells, "UNIT_SPELLCAST_SENT", "player") end
spells:SetScript("OnEvent", function(_, _, unit, _, _, spellID)
  if C.Data.disenchant[spellID] then deSnap = snap() end
end)
function C.NoteDELoot(guid, kind, id, qty)
  local e = deOpen[guid]
  if e and e.closed then return true end
  if not e then
    local src
    if C_Item and C_Item.GetItemIDByGUID then local ok, v = pcall(C_Item.GetItemIDByGUID, guid); if ok then src = v end end
    if not src and deSnap then -- the gear that left your bags since the cast
      local nowBags = snap()
      for bid, n in pairs(deSnap) do
        local r = C.Item(bid)
        if n > (nowBags[bid] or 0) and r and C.IsGear(r) and (r.q or 0) >= 2 then src = bid; break end
      end
    end
    local r = src and C.Item(src)
    if not (r and C.IsGear(r) and (r.q or 0) >= 2) then return false end
    e = addTrade({ kind = "disenchant", id = src, qty = 1, total = 0, out = {} })
    deOpen[guid] = e; deSnap = nil
    -- learn Forever's real disenchant results (20+ per kind replace the guide's table)
    local key = C.DETierKey(r)
    C.db.deObs = C.db.deObs or {}
    local o = C.db.deObs[key] or { n = 0, mats = {} }
    C.db.deObs[key] = o
    o.n = o.n + 1; e.obsKey = key
  end
  if id and kind ~= 2 then
    e.out[id] = (e.out[id] or 0) + (qty or 1)
    local o = C.db.deObs[e.obsKey]; if o then o.mats[id] = (o.mats[id] or 0) + (qty or 1) end
  end
  return true
end
C.On("LOOT_CLOSED", function() for _, e in pairs(deOpen) do e.closed = true end end)

------------------------------------------------------------------ trade reports
-- Value of disenchant materials at today's prices (after the cut), or nil
local function matsValue(out)
  local v, known = 0, true
  for mat, n in pairs(out or {}) do
    local u = C.Econ and C.Econ.MatNow and C.Econ.MatNow(mat)
    if u then v = v + u * n else known = false end
  end
  return v, known
end
C.MatsValue = matsValue

-- Flips: per item you BOUGHT to make money (on the AH, or from a vendor and then
-- listed on the AH), everything that happened to it since. Vendor sales of loot,
-- repairs and the rest stay in the log (farming uses them) but aren't flips.
local GAP = 10 * 60 -- a pause longer than this ends a trading stretch
function C.LedgerFlips(days)
  local cutoff = days and (C.Now() - days * 86400) or 0
  local list = T()
  -- items bought from a vendor count only if you then listed or sold them on the AH
  local resold = {}
  for _, e in ipairs(list) do if e.id and (e.kind == "post" or e.kind == "ahsale") then resold[e.id] = true end end
  local by = {}
  local function row(id) local r = by[id]; if not r then r = { id = id, bought = 0, paid = 0, de = 0, mats = {}, vendorN = 0, vendor = 0, ahN = 0, ah = 0, deposits = 0, first = math.huge, last = 0, events = {} }; by[id] = r end; return r end
  for _, e in ipairs(list) do
    if e.t >= cutoff and e.id and (e.kind == "ahbuy" or (e.kind == "vendorbuy" and resold[e.id])) then
      local r = row(e.id); r.bought = r.bought + (e.qty or 1); r.paid = r.paid - (e.total or 0)
      r.first = math.min(r.first, e.t); r.last = math.max(r.last, e.t); r.events[#r.events + 1] = e
    end
  end
  -- crafts, oldest first: used mats are done (at their cost), the product takes that cost
  for _, e in ipairs(list) do
    if e.t >= cutoff and e.kind == "craft" and e.used then
      local cost = 0
      for mat, n in pairs(e.used) do
        local m = by[mat]
        if m and m.bought > 0 and e.t >= m.first then
          local k = math.min(n, m.bought - (m.crafted or 0))
          if k > 0 then
            local each = m.paid / m.bought
            m.crafted = (m.crafted or 0) + k; m.craftCost = (m.craftCost or 0) + each * k
            cost = cost + each * k
            m.events[#m.events + 1] = { kind = "craftuse", t = e.t, qty = k, out = e.id, total = each * k }
            m.last = math.max(m.last, e.t)
          end
        end
      end
      if cost > 0 then
        local p = row(e.id)
        p.bought = p.bought + (e.qty or 1); p.paid = p.paid + cost; p.crafted0 = true
        p.first = math.min(p.first, e.t); p.last = math.max(p.last, e.t); p.events[#p.events + 1] = e
      end
    end
  end
  for _, e in ipairs(list) do
    local r = e.id and by[e.id]
    if r and e.t >= r.first and e.kind ~= "ahbuy" and e.kind ~= "vendorbuy" and e.kind ~= "craft" then
      if e.kind == "disenchant" then r.de = r.de + 1; for m, n in pairs(e.out or {}) do r.mats[m] = (r.mats[m] or 0) + n end
      elseif e.kind == "vendorsale" then r.vendorN = r.vendorN + (e.qty or 1); r.vendor = r.vendor + (e.total or 0)
      elseif e.kind == "ahsale" then r.ahN = r.ahN + (e.qty or 1); r.ah = r.ah + (e.total or 0)
      elseif e.kind == "post" then r.deposits = r.deposits + (e.deposit or 0) end
      r.last = math.max(r.last, e.t); r.events[#r.events + 1] = e
    end
  end
  local out = {}
  local have = C.Holdings and C.Holdings() or nil
  for _, r in pairs(by) do
    table.sort(r.events, function(a, b) return a.t < b.t end)
    r.avg = r.bought > 0 and r.paid / r.bought or 0
    r.matsNow, r.matsKnown = matsValue(r.mats)
    r.done = math.min(r.bought, r.de + r.vendorN + r.ahN + (r.crafted or 0))
    r.left = math.max(0, r.bought - r.done)
    -- never "holding" more than you actually own (bags, bank, AH listings)
    if have then r.left = math.min(r.left, have[r.id] or 0) end
    -- mats used in a craft: their cost went onto the crafted item (counted there)
    r.got = r.matsNow + r.vendor + r.ah + (r.craftCost or 0)
    -- deposits you paid come off (a sale's mail already returns its deposit)
    r.result = r.got - r.avg * r.done - r.deposits
    -- cash actually back from sales, apart from disenchant materials not sold yet
    r.realized = r.vendor + r.ah - r.avg * math.min(r.bought, r.vendorN + r.ahN) - r.deposits
    r.matsEstimate = r.matsNow
    r.roi = (r.done > 0 and r.avg > 0) and r.result / (r.avg * r.done) or nil
    out[#out + 1] = r
  end
  table.sort(out, function(a, b) return a.last > b.last end)
  return out
end

-- Time spent trading: every flip-related action, grouped into stretches (a gap of
-- 10+ minutes starts a new one); each stretch counts from its first action to its
-- last, plus 2 minutes. Returns hours.
function C.TradeHours(flips)
  local times = {}
  for _, r in ipairs(flips) do for _, e in ipairs(r.events) do times[#times + 1] = e.t end end
  table.sort(times)
  local secs, start, prev = 0, nil, nil
  for _, t in ipairs(times) do
    if not start then start = t
    elseif t - prev > GAP then secs = secs + (prev - start) + 120; start = t end
    prev = t
  end
  if start then secs = secs + (prev - start) + 120 end
  return secs / 3600
end
