-- Kina: fair group payouts.
-- 1. Split value: what a drop counts for when the group splits the loot. Items that
--    sell every day count at their price (never above the week's typical price, so a
--    spike isn't paid out). Green-or-lower items that hardly sell count at the money
--    the holder is sure to get: the vendor (or disenchanting, with an enchanter).
-- 2. Paid on sale: when the holder later sells one of those on the AH for more,
--    Kina says who is owed the difference, and the Pay button pays it.
-- 3. Pay button: opens a trade with the person you owe and puts in the exact money.
--    You both still press Trade yourselves.
local ADDON, C = ...

local function cut() return C.settings.ahCut or 0.05 end
local function first(n) return C.FirstName and C.FirstName(n) or (n and n:match("^([^%s%-]+)")) end

------------------------------------------------------------------ split value
-- Hardly sells: green or lower, and fewer than ~2 sold a day (gear with no sales
-- data counts as hardly selling; trade goods need a real market: 10+ listed in 3+ auctions).
function C.IsThinCheap(id)
  local ir = C.Item and C.Item(id)
  local q = ir and ir.q
  if q == nil or q > 2 then return false end
  local rate = C.Hot and C.Hot.GoneRate and C.Hot.GoneRate(id)
  if rate then return rate * 24 < 2 end
  if C.IsGear and C.IsGear(ir) then return true end
  local mi = C.MarketItem and C.MarketItem(id)
  return not (mi and (mi.q or 0) >= 10 and (mi.n or 0) >= 3)
end

-- copper one unit counts for in a group split
function C.SplitValue(id, suffix)
  local v, route = C.FarmValue(id, suffix)
  v = v or 0
  if route == "BOUND" then return 0, route end -- Bind on Pickup: nobody can sell it to you
  if C.IsThinCheap(id) then
    local _, _, det = C.BestRoute(id, 1)
    local floor = math.max(C.VendorPrice(id) or 0, det and det.de and det.de.ev or 0)
    v = (v > 0) and math.min(v, floor) or floor
    return math.floor(v), "floor"
  end
  local wk = C.WeekMedian and C.WeekMedian(id)
  if wk and route ~= "VENDOR" and route ~= "DISENCHANT" then
    local cap = wk * (1 - cut())
    local vend = C.VendorPrice(id) or 0
    if cap < v then v = math.max(cap, vend) end
  end
  return math.floor(v), route
end

------------------------------------------------------------------ paid on sale
-- At a shared farm's end: your own drops that were split at their floor price.
local function owedDB()
  C.db.payout = C.db.payout or { floors = {}, owed = {} }
  local p = C.db.payout
  p.floors = p.floors or {}; p.owed = p.owed or {}
  -- forget floors older than 3 weeks (the item was vendored, used or kept)
  for i = #p.floors, 1, -1 do if C.Now() - (p.floors[i].t or 0) > 21 * 86400 then table.remove(p.floors, i) end end
  return p
end
C.PayoutDB = owedDB

-- s: the stopped shared farm (s.sync = its log, s.split = the split)
function C.RecordFloors(s)
  if not (s and s.sync and s.sync.chain and s.split and s.split.incomes) then return end
  local me = first(UnitName("player"))
  local members, partners = 0, {}
  for who in pairs(s.split.incomes) do
    members = members + 1
    if first(who) ~= me then partners[#partners + 1] = who end
  end
  if members < 2 then return end
  local excluded, paused = {}, false
  for _, ev in ipairs(s.sync.chain) do
    if ev.kind == "E" then
      local seq, on = ev.data:match("^(%d+):(%d)$")
      if seq then excluded[tonumber(seq)] = (on == "1") or nil end
    end
  end
  local p = owedDB()
  for _, ev in ipairs(s.sync.chain) do
    if ev.kind == "P" then paused = ev.data == "1"
    elseif ev.kind == "L" and not paused and not excluded[ev.seq] and first(ev.origin) == me then
      local id, n, sfx, v = ev.data:match("^(%d*):(%d*):([^:]*):(%-?%d*)$")
      id, n, v = tonumber(id), tonumber(n) or 1, tonumber(v) or 0
      if id and not C.IsBound(id) and C.IsThinCheap(id) then
        p.floors[#p.floors + 1] = { id = id, n = n, v = v, sfx = (sfx ~= "" and sfx or nil), t = C.Now(),
          label = s.label, members = members, partners = partners }
      end
    end
  end
end

-- an AH sale mail (Ledger.lua): a floored drop sold for more? the partners get their share
function C.OnFarmItemSold(e)
  if not (e and e.kind == "sale" and e.id and (e.qty or 0) > 0) then return end
  local p = owedDB()
  local each = ((e.gross or 0) - (e.cut or 0)) / e.qty
  local left = e.qty
  local i = 1
  while i <= #p.floors and left > 0 do
    local f = p.floors[i]
    if f.id == e.id then
      local k = math.min(f.n, left)
      left = left - k; f.n = f.n - k
      local extra = (each - f.v) * k
      if extra > 0 then
        local share = math.floor(extra / f.members)
        if share > 0 then
          for _, who in ipairs(f.partners) do
            p.owed[who] = (p.owed[who] or 0) + share
            C.Print(string.format("|cffffd100%s|r from the %s farm sold for %s. The split counted it at %s, so you owe %s %s more (Pay button on the widget).",
              e.item or ("item " .. e.id), tostring(f.label or "group"), C.Money(math.floor(each)), C.Money(f.v), who, C.Money(share)))
          end
        end
      end
      if f.n <= 0 then table.remove(p.floors, i) else i = i + 1 end
    else i = i + 1 end
  end
  if C.RefreshWidget then C.RefreshWidget() end
end

------------------------------------------------------------------ pay button
-- What you owe next (oldest first): farm splits from the last 14 days, then sale top-ups.
function C.PayDue()
  for _, d in ipairs(C.Debts()) do
    if d.dir == "owe" and d.amt >= 1 then return { to = d.who, amt = math.floor(d.amt), kind = d.topup and "owed" or "split", s = d.s } end
  end
end

local function unitFor(name)
  local want = first(name)
  for i = 1, 4 do
    local u = "party" .. i
    if UnitExists(u) and first(UnitName(u)) == want then return u end
  end
  if IsInRaid and IsInRaid() then
    for i = 1, 40 do
      local u = "raid" .. i
      if UnitExists(u) and first(UnitName(u)) == want then return u end
    end
  end
  if UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") and first(UnitName("target")) == want then return "target" end
end
-- close enough to trade?
function C.PayInRange(due)
  local u = due and unitFor(due.to)
  if not u then return false end
  if not CheckInteractDistance then return true end
  local ok, near = pcall(CheckInteractDistance, u, 2)
  return ok and near and true or false
end

local pendingPay
function C.PayStart(due)
  if not due then return end
  local u = unitFor(due.to)
  pendingPay = { to = due.to, amt = due.amt, due = due, t = GetTime() }
  if u and InitiateTrade then
    InitiateTrade(u)
    C.Print(string.format("opening a trade with %s for %s...", due.to, C.Money(due.amt)))
  else
    C.Print(string.format("open a trade with %s: Kina will put in %s.", due.to, C.Money(due.amt)))
  end
end

C.On("TRADE_SHOW", function()
  local p = pendingPay
  if not p or GetTime() - p.t > 60 then pendingPay = nil; return end
  local them = UnitName and UnitName("NPC")
  if them and first(them) ~= first(p.to) then return end -- a trade with someone else
  local amt = math.min(p.amt, GetMoney and GetMoney() or p.amt)
  p.want = amt
  -- the trade window isn't ready the instant it opens: put the money in a moment
  -- later and keep trying until the game shows it (up to ~3 seconds)
  local tries = 0
  local function put()
    if pendingPay ~= p then return end
    tries = tries + 1
    if MoneyInputFrame_SetCopper and TradePlayerInputMoneyFrame then pcall(MoneyInputFrame_SetCopper, TradePlayerInputMoneyFrame, amt) end
    if SetTradeMoney then pcall(SetTradeMoney, amt) end
    local now = GetPlayerTradeMoney and GetPlayerTradeMoney() or nil
    if now == amt then
      p.set = amt
      C.Print(string.format("Kina put %s in the trade for %s.", C.Money(amt), p.to))
      C.AskAcceptTrade(string.format("Kina put %s in the trade for %s. Accept?", C.Money(amt), p.to))
    elseif tries < 10 then C.After(0.3, put)
    else
      C.Print(string.format("|cffff8040Kina couldn't put the money in. Type %s in the trade window yourself|r; Kina will offer Accept once it's there.", C.Money(amt)))
    end
  end
  C.After(0.2, put)
end)
-- the payer typed the money in by hand (or it arrived late): offer Accept only when it's right
C.On("TRADE_MONEY_CHANGED", function()
  local p = pendingPay
  if not (p and p.want and not p.set) then return end
  local now = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
  if now == p.want then
    p.set = now
    C.AskAcceptTrade(string.format("%s is in the trade for %s. Accept?", C.Money(now), p.to))
  end
end)

------------------------------------------------------------------ request settle
-- The person who is owed presses "Request" on the widget; the payer's Kina asks
-- "Pay?"; one click opens the trade with the money in; each side then accepts once.
-- The game needs a click from each player to finish a trade: Kina's Accept button is
-- that click (if the client refuses it, press the trade window's own Trade button).
local function popupAccept(text)
  if not StaticPopupDialogs then return end
  StaticPopupDialogs.KINA_TRADE_ACCEPT = StaticPopupDialogs.KINA_TRADE_ACCEPT or {
    text = "%s", button1 = "Accept trade", button2 = "Not yet", timeout = 60, whileDead = false, hideOnEscape = true,
    OnAccept = function()
      local ok = AcceptTrade and pcall(AcceptTrade)
      if not ok then C.Print("press Trade in the trade window to finish.") end
    end }
  StaticPopup_Show("KINA_TRADE_ACCEPT", text)
end
C.AskAcceptTrade = popupAccept

-- money you are owed (oldest first), not yet received
function C.ReceiveDue()
  if C.session then return nil end
  for _, d in ipairs(C.Debts()) do
    if d.dir == "owed" and d.amt >= 1 then return { from = d.who, amt = math.floor(d.amt), s = d.s } end
  end
end
local expecting -- { from, amt, s, t }
function C.RequestSettle(due)
  if not (due and C.Share and C.Share.SendSettle) then return end
  expecting = { from = due.from, amt = due.amt, s = due.s, t = GetTime() }
  C.Share.SendSettle("req", due.from, due.amt, due.s and due.s.label or "farm")
  C.Print(string.format("asked %s to settle %s. Stay close: they get a Pay popup.", C.Books.Name(due.from), C.Money(due.amt)))
end
-- the payer's side: a request arrived
function C.OnSettleRequest(from, amt, label)
  local due = C.PayDue()
  if not due or first(due.to) ~= first(from) then
    C.Print(string.format("%s asked you to settle %s, but Kina has no matching debt (check your farm log).", tostring(from), C.Money(amt or 0)))
    return
  end
  if not StaticPopupDialogs then return end
  StaticPopupDialogs.KINA_SETTLE_REQ = StaticPopupDialogs.KINA_SETTLE_REQ or {
    text = "%s asks you to settle %s for the %s farm.", button1 = "Pay", button2 = "Not now", timeout = 120, hideOnEscape = true,
    OnAccept = function() C.PayStart(C.PayDue()) end }
  StaticPopup_Show("KINA_SETTLE_REQ", tostring(from), C.Money(due.amt), tostring(label or "group"))
end
-- the receiver's side: the payer put money in the trade
C.On("TRADE_MONEY_CHANGED", function()
  local e = expecting
  if not e or GetTime() - e.t > 300 then return end
  local them = UnitName and UnitName("NPC")
  if them and first(them) ~= first(e.from) then return end
  local m = GetTargetTradeMoney and GetTargetTradeMoney() or 0
  if m >= e.amt then popupAccept(string.format("%s put in %s (you're owed %s).", e.from, C.Money(m), C.Money(e.amt))) end
end)

------------------------------------------------------------------ what actually moved
-- Kina never trusts what it asked for: it records what the trade window really held
-- when the trade completed (both sides see the same window), and applies exactly that
-- to the debts in both directions. A short payment leaves the rest owed; a cancelled
-- trade changes nothing; a trade nobody asked for still settles what it covers.
local tr -- the open (or just closed) trade: { who, mine, theirs, closed }
local function readTrade()
  if not tr or tr.closed then return end
  if GetPlayerTradeMoney then tr.mine = GetPlayerTradeMoney() or tr.mine end
  if GetTargetTradeMoney then tr.theirs = GetTargetTradeMoney() or tr.theirs end
end
local function stats()
  local t = C.db.tradeStats
  if type(t) ~= "table" then t = { complete = 0, missed = 0, cancelled = 0, msgs = {} }; C.db.tradeStats = t end
  t.msgs = type(t.msgs) == "table" and t.msgs or {}
  return t
end
local function completed(t, how)
  if t.done then return end
  t.done = true
  pendingPay, expecting = nil, nil
  local st = stats()
  if how == "message" then st.complete = (st.complete or 0) + 1 else st.missed = (st.missed or 0) + 1; st.lastMissed = C.Now() end
  if t.who and ((t.mine or 0) > 0 or (t.theirs or 0) > 0) then C.SettleMoved(t.who, t.mine or 0, t.theirs or 0, "trade") end
end
C.On("TRADE_SHOW", function()
  tr = { who = UnitName and UnitName("NPC"), mine = 0, theirs = 0, money0 = GetMoney and GetMoney() }
  readTrade()
end)
C.On("TRADE_MONEY_CHANGED", readTrade)
C.On("TRADE_ACCEPT_UPDATE", readTrade)
C.On("TRADE_CLOSED", function()
  if not tr or tr.closed then return end
  tr.closed = GetTime()
  -- safety net: if the game never says "Trade complete." (a different message on this
  -- client), the gold that actually moved still tells: exactly their money minus ours
  local t = tr
  C.After(2, function()
    if t.done or t.cancelled or not (GetMoney and t.money0) then return end
    local want = (t.theirs or 0) - (t.mine or 0)
    if want ~= 0 and GetMoney() - t.money0 == want then completed(t, "money") end
  end)
end)
C.On("UI_INFO_MESSAGE", function(_, a, b)
  local msg = (type(b) == "string" and b) or (type(a) == "string" and a) or nil
  if not msg or not tr then return end
  -- what this client says around trades (for /kina selftest)
  local st = stats()
  table.insert(st.msgs, 1, msg); while #st.msgs > 5 do table.remove(st.msgs) end
  if msg == (ERR_TRADE_COMPLETE or "Trade complete.") then
    local t = tr; tr = nil
    completed(t, "message")
  elseif msg == ERR_TRADE_CANCELLED or msg == "Trade cancelled." then
    tr.cancelled = true; tr = nil
    st.cancelled = (st.cancelled or 0) + 1
    if pendingPay then pendingPay.set = nil end -- try again with the button
  end
end)

------------------------------------------------------------------ settle by mail
-- At the mailbox: everyone you owe and everyone who owes you (farms in the last 14
-- days, plus AH-sale top-ups). Tick rows and press Send: Kina mails the money you owe,
-- or mails a polite request for money owed to you. Money that arrives in a "Kina
-- settle" mail marks that debt as paid.
local SUBJ = "Kina settle"
-- how much of a split transfer is still open (paid/received hold amounts; true = all)
local function left(map, key, amt)
  local v = map and map[key]
  if v == true then return 0 end
  return math.max(0, amt - (tonumber(v) or 0))
end
function C.Debts()
  local me = first(UnitName("player"))
  local out = {}
  for _, s in ipairs(C.db.sessions or {}) do
    if s.stop and C.Now() - s.stop > 14 * 86400 then break end
    local sp = s.split
    if sp and sp.transfers then
      sp.paid = sp.paid or {}; sp.received = sp.received or {}
      for _, t in ipairs(sp.transfers) do
        if (first(t.from) == me or t.from == "you") and t.amt > 0 then
          local rest = left(sp.paid, t.to, t.amt)
          if rest >= 1 then out[#out + 1] = { dir = "owe", who = t.to, amt = rest, farm = s.label or "farm", t = s.stop or s.start, s = s, key = t.to, tr = t } end
        elseif (first(t.to) == me or t.to == "you") and t.amt > 0 then
          local rest = left(sp.received, t.from, t.amt)
          if rest >= 1 then out[#out + 1] = { dir = "owed", who = t.from, amt = rest, farm = s.label or "farm", t = s.stop or s.start, s = s, key = t.from, tr = t } end
        end
      end
    end
  end
  -- oldest first: a payment settles the oldest debt first, on both sides alike
  local farms = {}
  for i = #out, 1, -1 do farms[#farms + 1] = out[i] end
  out = farms
  for who, amt in pairs(owedDB().owed) do
    if amt >= 1 then out[#out + 1] = { dir = "owe", who = who, amt = amt, farm = "AH sale top-ups", t = nil, topup = true } end
  end
  return out
end
local function markPaid(d, amt)
  if amt <= 0 then return end
  if d.topup then
    local o = owedDB().owed
    o[d.who] = math.max(0, (o[d.who] or 0) - amt); if o[d.who] < 1 then o[d.who] = nil end
  elseif d.s and d.s.split then
    local map = d.dir == "owe" and d.s.split.paid or d.s.split.received
    local done = map[d.key] == true and math.huge or (tonumber(map[d.key]) or 0)
    done = done + amt
    -- (this debt's own transfer: with 3+ players, someone else may owe the same person)
    local full = d.tr and d.tr.amt
    map[d.key] = (full and done >= full - 0.5) and true or done
  end
end
-- money really moved between you and who (trade or mail): pay down what you owe them
-- with what you gave, and what they owe you with what you got. Logged, and confirmed
-- with their Kina.
function C.SettleMoved(who, gave, got, via)
  who = first(who)
  if not who then return end
  local usedGave, usedGot = 0, 0
  local covers = {} -- which farm's debt each part paid (the Ledger shows it per farm)
  for _, d in ipairs(C.Debts()) do
    if first(d.who) == who then
      local k = 0
      if d.dir == "owe" and gave - usedGave >= 1 then
        k = math.min(d.amt, gave - usedGave); markPaid(d, k); usedGave = usedGave + k
      elseif d.dir == "owed" and got - usedGot >= 1 then
        k = math.min(d.amt, got - usedGot); markPaid(d, k); usedGot = usedGot + k
      end
      if k > 0 then covers[#covers + 1] = { start = d.s and d.s.start, label = d.farm, amt = math.floor(k), dir = d.dir, topup = d.topup or nil } end
    end
  end
  C.db.settles = C.db.settles or {}
  local rec = { t = C.Now(), who = who, gave = gave, got = got, via = via, paidOff = usedGave, cameIn = usedGot, covers = covers }
  table.insert(C.db.settles, 1, rec)
  while #C.db.settles > 200 do table.remove(C.db.settles) end
  -- their confirmation may have arrived before our own trade/mail event
  if C.pendingConf then
    local keep = {}
    for _, pc in ipairs(C.pendingConf) do
      if C.Now() - pc.t < 600 and not (first(pc.from) == who and not rec.conf and C._matchConf(rec, pc.gave, pc.label)) then keep[#keep + 1] = pc end
    end
    C.pendingConf = keep
  end
  if C.Log then C.Log("moved", via, who, gave, got, usedGave, usedGot) end
  if usedGave > 0 then C.Print(string.format("|cff7CFC00paid %s %s.|r", who, C.Money(usedGave))) end
  if usedGot > 0 then C.Print(string.format("|cff7CFC00%s paid you %s.|r", who, C.Money(usedGot))) end
  local still = 0
  for _, d in ipairs(C.Debts()) do if first(d.who) == who then still = still + d.amt end end
  if (usedGave > 0 or usedGot > 0) and still >= 1 then C.Print(string.format("%s still open with %s.", C.Money(still), who)) end
  -- tell their Kina what we saw, so both records can be matched
  if C.Share and C.Share.SendSettle and (gave > 0 or got > 0) then
    pcall(C.Share.SendSettle, "cnf", who, gave, via .. ":" .. math.floor(got))
  end
  if C.RefreshWidget then C.RefreshWidget() end
  if C.RefreshSettle then C.RefreshSettle() end
end
-- their Kina saw the same money move: mark our record confirmed (both sides agree)
function C._matchConf(r, theirGave, label)
  local via, theirGot = tostring(label or ""):match("^(%a+):(%d+)$")
  theirGot = tonumber(theirGot) or 0
  if r.via == via and r.got == theirGave and r.gave == theirGot then
    r.conf = C.Now()
    if C.Log then C.Log("confirmed", via, r.who, r.gave, r.got, r.paidOff, r.cameIn) end
    return true
  end
end
function C.OnSettleConfirm(from, theirGave, label)
  for _, r in ipairs(C.db.settles or {}) do
    if C.Now() - r.t > 600 then break end
    if first(r.who) == first(from) and not r.conf and C._matchConf(r, theirGave, label) then return true end
  end
  -- not seen yet (their message came first): keep it a moment
  C.pendingConf = C.pendingConf or {}
  table.insert(C.pendingConf, { from = from, gave = theirGave, label = label, t = C.Now() })
end
local function plainMoney(c) return (C.Money(c):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function mailName(who)
  return (C.GroupMemberName and C.GroupMemberName(who)) or who
end

local queue, sending = {}, nil
local function sendNext()
  sending = table.remove(queue, 1)
  if not sending then if C.RefreshSettle then C.RefreshSettle() end; return end
  local d = sending
  local to = mailName(d.who)
  if d.dir == "owe" then
    if math.floor(d.amt) > (GetMoney and GetMoney() or 0) then
      C.Print("not enough gold to pay " .. d.who .. ".")
      sending = nil; return sendNext()
    end
    if SetSendMailMoney then SetSendMailMoney(math.floor(d.amt)) end
    SendMail(to, SUBJ .. ": " .. plainMoney(d.amt) .. " (" .. d.farm .. ")",
      "Paying my share of the " .. d.farm .. " farm, as Kina worked it out. Thanks for farming!")
  else
    SendMail(to, "Kina: please settle (" .. d.farm .. ")",
      string.format("Hi! Kina says you owe me %s from the %s farm. When you get a moment, open your mailbox: Kina will offer to send it. Thanks!",
        plainMoney(d.amt), d.farm))
  end
end
C.On("MAIL_SEND_SUCCESS", function()
  local d = sending
  if not d then return end
  if d.dir == "owe" then C.SettleMoved(d.who, math.floor(d.amt), 0, "mail")
  else C.Print("asked " .. d.who .. " to settle (mail sent).") ; d.asked = true end
  C.After(0.6, sendNext)
end)
C.On("MAIL_FAILED", function()
  if sending then C.Print("|cffff8040mail to " .. sending.who .. " failed|r (wrong name or realm?). The rest were not sent.") end
  sending = nil; queue = {}
  if C.RefreshSettle then C.RefreshSettle() end
end)
-- money that arrives in a Kina settle mail pays off that person's debt to you (once:
-- the mails already counted are remembered in the saved data, so a reload can't count
-- the same letter twice)
C.On("MAIL_INBOX_UPDATE", function()
  if not GetInboxNumItems or not GetInboxHeaderInfo then return end
  C.db.seenMail = C.db.seenMail or {}
  local seen = C.db.seenMail
  for k, t in pairs(seen) do if C.Now() - t > 35 * 86400 then seen[k] = nil end end
  for i = 1, GetInboxNumItems() do
    local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    if sender and subject and money and money > 0 and subject:sub(1, #SUBJ) == SUBJ then
      local key = sender .. "|" .. subject .. "|" .. money .. "|" .. tostring(math.floor((daysLeft or 0) * 24))
      if not seen[key] then
        seen[key] = C.Now()
        C.SettleMoved(sender, 0, money, "mail")
      end
    end
  end
  if C.RefreshSettle then C.RefreshSettle() end
end)

local sf
function C.RefreshSettle()
  if not (sf and sf:IsShown()) then return end
  local debts = C.Debts()
  sf.debts = debts
  for i, row in ipairs(sf.rows) do
    local d = debts[i]
    if d then
      row.d = d
      row.cb:Show(); row.text:Show()
      local when = d.t and date and date("%b %d", d.t) or "-"
      row.text:SetText(string.format("%s  |cffffd100%s|r  %s  %s  %s", when, d.who, d.farm,
        d.dir == "owe" and "|cffff8080you owe|r" or "|cff7CFC00owes you|r", C.Money(d.amt)))
    else row.d = nil; row.cb:Hide(); row.text:Hide(); row.cb:SetChecked(false) end
  end
  sf.empty:SetText(#debts == 0 and "Nobody owes anybody. Nice." or "")
end
function C.ShowSettle()
  if not sf then
    local f = CreateFrame("Frame", "KinaSettle", UIParent)
    f:SetSize(430, 330); f:EnableMouse(true); if f.SetToplevel then f:SetToplevel(true) end
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    local title = C.Text(f, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 12, -10); title:SetText("Kina: settle up")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 0, 0)
    f.rows = {}
    for i = 1, 10 do
      local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
      cb:SetSize(22, 22); cb:SetPoint("TOPLEFT", 10, -32 - (i - 1) * 24)
      local t = C.Text(f, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
      if C.ButtonTip then C.ButtonTip(cb, "Settle this one", "Ticked: pressing Send mails them the money you owe, or mails them a friendly request for the money they owe you.") end
      f.rows[i] = { cb = cb, text = t }
    end
    f.empty = C.Text(f, "OVERLAY", "GameFontDisableSmall"); f.empty:SetPoint("TOPLEFT", 14, -36)
    local send = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    send:SetSize(140, 22); send:SetPoint("BOTTOMLEFT", 10, 10); send:SetText("Send selected")
    send:SetScript("OnClick", function()
      queue = {}
      for _, row in ipairs(f.rows) do if row.d and row.cb:GetChecked() then queue[#queue + 1] = row.d; row.cb:SetChecked(false) end end
      if #queue == 0 then C.Print("tick who to settle with first."); return end
      sendNext()
    end)
    if C.ButtonTip then C.ButtonTip(send, "Send selected", "Mails the money you owe to everyone ticked (postage applies), and a request to everyone ticked who owes you. Paid debts drop off this list.") end
    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    all:SetSize(110, 22); all:SetPoint("LEFT", send, "RIGHT", 6, 0); all:SetText("Tick all")
    all:SetScript("OnClick", function() for _, row in ipairs(f.rows) do if row.d then row.cb:SetChecked(true) end end end)
    if C.ButtonTip then C.ButtonTip(all, "Tick all", "Selects every row, so one Send settles everything.") end
    sf = f
  end
  sf:ClearAllPoints()
  if MailFrame and MailFrame:IsShown() then sf:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0) else sf:SetPoint("CENTER") end
  sf:Show(); C.RefreshSettle()
end
-- the mailbox opens: show it when there is something to settle
C.On("MAIL_SHOW", function()
  C.After(0.3, function() if #C.Debts() > 0 then C.ShowSettle() end end)
end)
C.On("MAIL_CLOSED", function() if sf then sf:Hide() end end)
