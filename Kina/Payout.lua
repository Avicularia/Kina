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

-- 1.3.1 (Taylor, Nov 6): an item worth money only on the AH (vendor pays under a quarter
-- of its AH price) is split at its vendor price; when the looter actually sells it, the
-- partners get their share of the real sale price as a top-up (paid on sale).
function C.IsAHOnly(id)
  if C.IsBound and C.IsBound(id) then return false end
  local _, route, det = C.BestRoute(id, 1)
  local ah = det and det.ah or 0
  local vend = C.VendorPrice(id) or 0
  return ah > 0 and vend < ah * 0.25
end
function C.IsFloored(id) return C.IsThinCheap(id) or C.IsAHOnly(id) end
-- copper one unit counts for in a group split
function C.SplitValue(id, suffix)
  local v, route = C.FarmValue(id, suffix)
  v = v or 0
  if route == "BOUND" then return 0, route end -- Bind on Pickup: nobody can sell it to you
  -- 1.2.5 (Taylor): enchanting material prices are crashing faster than scans keep up,
  -- so a looted green priced at its disenchant value charged the looter for dust worth
  -- half that by the time it sold. Until the "actual outcome" rule ships, the split never
  -- counts a disenchant guess: gear counts at its vendor or AH value, and what the
  -- enchanter does with it is theirs.
  if route == "DISENCHANT" then
    local _, _, det = C.BestRoute(id, 1)
    local vend = C.VendorPrice(id) or 0
    local ah = det and det.ah or 0
    if ah > vend then return math.floor(ah), "AH" end
    return math.floor(vend), "VENDOR"
  end
  if C.IsFloored(id) then
    local _, _, det = C.BestRoute(id, 1)
    local floor = C.VendorPrice(id) or 0
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
      if id and not C.IsBound(id) and C.IsFloored(id) then
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
            C.Print(string.format("|cffffc54a%s|r from the %s farm sold for %s. The split counted it at %s, so you owe %s %s more (Pay button on the widget).",
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
-- 1.2.6: the whole amount owed to one person (every open farm with them), so the widget's
-- line and button agree and one payment settles them all (payments spread over the debts)
local function firstOf(n) return n and (n:match("^([^%-]+)") or n) end
function C.PayDue()
  local due
  for _, d in ipairs(C.Debts()) do
    if d.dir == "owe" and d.amt >= 1 then
      if not due then due = { to = d.who, amt = 0, kind = d.topup and "owed" or "split", s = d.s, n = 0 } end
      if firstOf(d.who) == firstOf(due.to) then due.amt = due.amt + d.amt; due.n = due.n + 1 end
    end
  end
  if due then due.amt = math.floor(due.amt) end
  return due
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
  -- 0.9.8: the person you owe asked you to settle and opened this trade: pay them
  local them0 = UnitName and UnitName("NPC")
  local ask = them0 and C.settleAsks and C.settleAsks[first(them0)]
  if ask and GetTime() - ask.t < 120 and not (pendingPay and GetTime() - pendingPay.t < 60) then
    C.settleAsks[first(them0)] = nil
    pendingPay = { to = ask.due.to, amt = ask.due.amt, due = ask.due, t = GetTime() }
    if StaticPopup_Hide then pcall(C.HidePopup, "KINA_SETTLE_REQ") end
  end
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
    -- 1.2.4: on Forever only Blizzard's own UI may put money in a trade (Kina trying it
    -- pops "blocked from an action"), so Kina never touches the gold box: it says the
    -- exact amount to type and offers Accept once it's right
    if SetTradeMoney and not C.tradeMoneyProtected then pcall(SetTradeMoney, amt) end
    local now = GetPlayerTradeMoney and GetPlayerTradeMoney() or nil
    if now == amt then
      p.set = amt
      C.Print(string.format("Kina put %s in the trade for %s.", C.Money(amt), p.to))
      C.AskAcceptTrade(string.format("Kina put %s in the trade for %s. Accept?", C.Money(amt), p.to))
    elseif not SetTradeMoney or C.tradeMoneyProtected then
      C.Print(string.format("|cffffc54aType %s in the trade window's gold box|r; Kina offers Accept once it's there.", C.Money(amt)))
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
  if not C.Dialogs then return end
  C.Dialogs.KINA_TRADE_ACCEPT = C.Dialogs.KINA_TRADE_ACCEPT or {
    text = "%s", button1 = "Accept trade", button2 = "Not yet", timeout = 60, whileDead = false, hideOnEscape = true,
    OnAccept = function()
      local ok = AcceptTrade and pcall(AcceptTrade)
      if not ok then C.Print("press Trade in the trade window to finish.") end
    end }
  C.ShowPopup("KINA_TRADE_ACCEPT", text)
end
C.AskAcceptTrade = popupAccept

-- money you are owed (oldest first), not yet received
function C.ReceiveDue()
  if C.session then return nil end
  local due
  for _, d in ipairs(C.Debts()) do
    if d.dir == "owed" and d.amt >= 1 then
      if not due then due = { from = d.who, amt = 0, s = d.s, n = 0 } end
      if firstOf(d.who) == firstOf(due.from) then due.amt = due.amt + d.amt; due.n = due.n + 1 end
    end
  end
  if due then due.amt = math.floor(due.amt) end
  return due
end
local expecting -- { from, amt, s, t }
function C.RequestSettle(due)
  if not (due and C.Share and C.Share.SendSettle) then return end
  expecting = { from = due.from, amt = due.amt, s = due.s, t = GetTime() }
  C.Share.SendSettle("req", due.from, due.amt, due.s and due.s.label or "farm")
  -- 0.9.8 (Taylor): Ask to pay opens the trade too when they're close enough; their Kina
  -- puts the amount in for them (it knows the debt) and they just accept
  local u = unitFor(due.from)
  local near = u and (not CheckInteractDistance or CheckInteractDistance(u, 2))
  if near and InitiateTrade then
    pcall(InitiateTrade, u)
    C.Print(string.format("asked %s to settle %s and opened a trade: their Kina puts the money in.", C.Books.Name(due.from), C.Money(due.amt)))
  else
    C.Print(string.format("asked %s to settle %s. Stand next to them to trade: they also get a Pay popup.", C.Books.Name(due.from), C.Money(due.amt)))
  end
end
-- the payer's side: a request arrived
C.settleAsks = {}
function C.OnSettleRequest(from, amt, label)
  local due = C.PayDue()
  -- (0.9.8: the debt to THIS person, not just the first one due)
  for _, d in ipairs(C.Debts()) do
    if d.dir == "owe" and first(d.who) == first(from) and d.amt >= 1 then due = { to = d.who, amt = math.floor(d.amt), s = d.s }; break end
  end
  if due and first(due.to) == first(from) then C.settleAsks[first(from)] = { t = GetTime(), due = due } end
  if not due or first(due.to) ~= first(from) then
    C.Print(string.format("%s asked you to settle %s, but Kina has no matching debt (check your farm log).", tostring(from), C.Money(amt or 0)))
    return
  end
  if not C.Dialogs then return end
  C.Dialogs.KINA_SETTLE_REQ = C.Dialogs.KINA_SETTLE_REQ or {
    text = "%s asks you to settle %s.", button1 = "Pay", button2 = "Not now", timeout = 120, hideOnEscape = true,
    -- 0.9.13 (exploit test): pay the person who asked (it paid your first debt, whoever that was to)
    OnAccept = function(_, data) C.PayStart(data or C.PayDue()) end }
  C.ShowPopup("KINA_SETTLE_REQ", tostring(from), C.Money(due.amt) .. " for the " .. tostring(label or "group") .. " farm", due)
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
C.On("TRADE_ACCEPT_UPDATE", function(_, me, them)
  readTrade()
  if tr and not tr.closed then
    -- 0.9.1 (security): remember WHEN each side accepted and drop it when they take it
    -- back; an offer only counts if it stood long enough for the other side to take it
    local now = GetTime and GetTime() or 0
    if me == 1 or me == true then tr.iAcc = true; tr.iAccAt = tr.iAccAt or now else tr.iAcc, tr.iAccAt = nil, nil end
    if them == 1 or them == true then tr.theyAcc = true; tr.theyAccAt = tr.theyAccAt or now else tr.theyAcc, tr.theyAccAt = nil, nil end
  end
end)
-- 1.3.0: a payment offered and turned down. The debtor put the whole amount in the trade
-- and accepted, the creditor didn't, and the trade was cancelled: both Kinas note it.
-- If that debt then runs out of time, it doesn't count against the debtor; the creditor's
-- Kina takes the hit instead (-50 rep, -100 for a second time within 30 days).
C.OFFER_STAND = 15 -- seconds an accepted full payment must stand before a cancel counts as refused
local function noteRefusal(t)
  if not (t and t.who) then return end
  -- 0.9.1 (security): accepting and cancelling at once was a free "offer" that pushed the
  -- penalty onto the creditor; now the accepted offer must have stood 15 seconds
  local now = GetTime and GetTime() or 0
  if t.iAcc and not (t.iAccAt and now - t.iAccAt >= C.OFFER_STAND) then t.iAcc = nil end
  if t.theyAcc and not (t.theyAccAt and now - t.theyAccAt >= C.OFFER_STAND) then t.theyAcc = nil end
  local who = t.who:match("^[^%-]+")
  for _, d in ipairs(C.Debts()) do
    if (d.who or ""):match("^[^%-]+") == who and d.s and not d.topup then
      local sp = d.s.split or {}; d.s.split = sp
      if d.dir == "owe" and t.iAcc and not t.theyAcc and (t.mine or 0) >= math.floor(d.amt) then
        sp.offered = sp.offered or {}; sp.offered[d.key] = C.Now()
        C.Print(string.format("|cffffc54aKina noted that you offered %s the full %s and the trade was cancelled.|r If they never take it, the debt won't count against you.", C.Books.Name(d.who), C.Money(math.floor(d.amt))))
      elseif d.dir == "owed" and t.theyAcc and not t.iAcc and (t.theirs or 0) >= math.floor(d.amt) then
        sp.refusedSeen = sp.refusedSeen or {}; sp.refusedSeen[d.key] = C.Now()
        C.Print(string.format("|cffff8040%s offered the full %s and the trade was cancelled.|r If the debt runs out of time after an offer, it costs YOUR standing, not theirs.", C.Books.Name(d.who), C.Money(math.floor(d.amt))))
      end
    end
  end
end
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
    tr.cancelled = true
    pcall(noteRefusal, tr)
    tr = nil
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
    -- (0.9.2: a lapsed debt can still be paid late for 60 days, from Collections)
    if s.stop and C.Now() - s.stop > 60 * 86400 then break end
    local old = s.stop and C.Now() - s.stop > 14 * 86400
    local sp = s.split
    if sp and sp.transfers and not (s.hold and not s.hold.done) then -- (0.9.0: not while waiting for AH prices)
      sp.paid = sp.paid or {}; sp.received = sp.received or {}
      for _, t in ipairs(sp.transfers) do
        local who = (first(t.from) == me or t.from == "you") and t.to or t.from
        if old and not (sp.lapsed and sp.lapsed[who]) then
          -- older than 14 days and not lapsed: nothing to pay
        elseif (first(t.from) == me or t.from == "you") and t.amt > 0 then
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
------------------------------------------------------------------ forgive (1.0.10)
-- The person owed can forgive what's left of a debt at any time. Their Kina tells the
-- debtor's Kina (re-sent until it answers), and the debt closes on both sides.
-- 1.0.5: a name that is me on any of my characters
local function isMine(n) n = first(n); return n ~= nil and n ~= "" and (n == first(UnitName and UnitName("player") or "") or (C.IsMyChar and C.IsMyChar(n)) or false) end
local function farmRef(s) return (s and s.sync and s.sync.sid) or ("t" .. tostring(s and s.start or 0)) end
local function fdb() C.db.forgive = C.db.forgive or { pending = {} }; C.db.forgive.pending = C.db.forgive.pending or {}; return C.db.forgive end
local function sendForgive(p)
  if C.Share and C.Share.SendForgive then pcall(C.Share.SendForgive, p.who, p.amt, p.ref, p.kind) end
end
-- 1.0.5 (Taylor: "we click Dispute and nothing happens"): a dispute names the character the
-- debt is on ("ref~Deputize"), so the other side finds the farm whichever alt you're on now
local function splitRef(ref)
  local base, ch = tostring(ref or ""):match("^([^~]*)~(.*)$")
  return base or tostring(ref or ""), ch
end
C._SplitRef = splitRef
-- requests waiting for MY answer (a dispute someone sent me): kept until I answer, shown
-- again at login, so a closed popup or a logout never loses one
local function asks() fdb().asks = fdb().asks or {}; return fdb().asks end
local function askKey(from, ref) return tostring(first(from)) .. "|" .. tostring(ref) end
local function answered(from, ref)
  local a = asks(); a[askKey(from, ref)] = nil
end
C._Asks = asks
-- every note gets a receipt from the other Kina ("rcv"): a request (dispute, plea) then
-- waits for the person's answer; anything else is done once it arrived
local NEEDS_ANSWER = { dsp = true, plea = true, ext = true }
function C.SendReceipt(to, kind, ref)
  if C.Share and C.Share.SendForgive then pcall(C.Share.SendForgive, first(to), 0, tostring(kind or "fgv") .. ":" .. tostring(ref or ""), "rcv") end
end
function C.OnReceipt(from, label)
  local kind, ref = tostring(label or ""):match("^(%a+):(.*)$")
  if not kind then return end
  from = first(from)
  local keep = {}
  for _, p in ipairs(fdb().pending) do
    if p.who == from and p.ref == ref and (p.kind or "fgv") == kind then
      if NEEDS_ANSWER[kind] then
        if not p.got then
          p.got = C.Now()
          C.Print(string.format("|cff7CFC00%s's Kina got your %s.|r Waiting for their answer.", C.Books and C.Books.Name(from) or from, kind == "dsp" and "dispute" or "request"))
        end
        keep[#keep + 1] = p
      end
    else keep[#keep + 1] = p end
  end
  fdb().pending = keep
  if C.Refresh then pcall(C.Refresh) end
end
function C.Forgive(d)
  if not (d and d.dir == "owed" and d.s and d.s.split) then return false end
  local sp = d.s.split
  sp.received = sp.received or {}
  sp.received[d.key] = true
  sp.forgiven = sp.forgiven or {}; sp.forgiven[d.key] = math.floor(d.amt)
  if C.Log then C.Log("forgive", "gave", d.who, math.floor(d.amt), farmRef(d.s)) end
  local p = { who = first(d.who), amt = math.floor(d.amt), ref = farmRef(d.s), t = C.Now() }
  table.insert(fdb().pending, p)
  sendForgive(p)
  C.Print(string.format("|cff7CFC00You forgave %s %s|r (%s). Their Kina closes it too.", C.Books and C.Books.Name(d.who) or d.who, C.Money(math.floor(d.amt)), d.farm or "farm"))
  if C.RefreshWidget then C.RefreshWidget() end
  if C.Refresh then C.Refresh() end
  return true
end
-- the debtor's side: someone forgave what we owed them on one farm
-- 1.0.2b (Taylor: "Scarlet forgave my debt but it's still there"): the farm can be waiting
-- for AH prices on my side (Debts() hides those) - the forgiveness found nothing, was
-- still confirmed, and the forgiver's Kina stopped sending it: lost. Now the farm is
-- looked up directly, held or not, and it's only confirmed once it's applied (until then
-- the forgiver's Kina keeps re-sending it).
function C.OnForgiven(from, amt, ref)
  from = first(from)
  local rawRef = ref
  ref = splitRef(ref)
  local me = first(UnitName and UnitName("player") or "")
  local hit = false
  local function apply(s, t)
    local sp = s.split
    sp.paid = sp.paid or {}
    if sp.paid[t.to] == true then return end
    local left = math.floor(t.amt or 0)
    if type(sp.paid[t.to]) == "number" then left = left - sp.paid[t.to] end
    sp.paid[t.to] = true
    sp.forgiven = sp.forgiven or {}; sp.forgiven[t.to] = math.max(0, left)
    if C.Log then C.Log("forgive", "got", from, math.max(0, left), ref) end
    C.Print(string.format("|cff7CFC00%s forgave the %s you owed them|r (%s). Nothing to pay.", C.Books and C.Books.Name(from) or from, C.Money(math.max(0, left)), s.label or "farm"))
    hit = true
  end
  for _, s in ipairs(C.db.sessions or {}) do
    if s.split and s.split.transfers and farmRef(s) == ref then
      for _, t in ipairs(s.split.transfers) do
        if (t.from == "you" or first(t.from) == me or isMine(t.from)) and first(t.to) == from then apply(s, t) end
      end
      if not hit and s.split.paid and s.split.paid[from] == true then hit = true end -- already done (a re-send)
      for k in pairs(s.split.paid or {}) do if first(k) == from and s.split.paid[k] == true then hit = true end end
    end
  end
  -- an older single-player farm, matched by amount
  if not hit and type(ref) == "string" and ref:sub(1, 1) == "t" then
    for _, d in ipairs(C.Debts()) do
      if not hit and d.dir == "owe" and not d.topup and first(d.who) == from and math.abs(d.amt - (amt or 0)) < 1 then
        local sp = d.s.split
        sp.paid = sp.paid or {}; sp.paid[d.key] = true
        sp.forgiven = sp.forgiven or {}; sp.forgiven[d.key] = math.floor(d.amt)
        if C.Log then C.Log("forgive", "got", from, math.floor(d.amt), ref) end
        hit = true
      end
    end
  end
  if hit and C.Share and C.Share.SendForgiveAck then pcall(C.Share.SendForgiveAck, from, rawRef) end
  C.SendReceipt(from, "fgv", rawRef)
  if hit then C.OnForgiveAck(from, rawRef, "dsp"); if rawRef ~= ref then C.OnForgiveAck(from, ref, "dsp") end end
  if C.RefreshWidget then C.RefreshWidget() end
  if C.Refresh then pcall(C.Refresh) end
  return hit
end
-- 1.0.2b (Taylor: "I need a way to remove or dispute that debt, and so does everyone"):
-- the one who owes asks the one owed to clear a debt ("it was forgiven / already paid").
-- The one owed decides: Clear it (a forgiveness, so the lapse penalty is given back too)
-- or It's still owed. If their Kina already shows it forgiven or paid, it just sends the
-- forgiveness again, no question. The request waits and re-sends until it's answered.
function C.DisputeDebt(d, why)
  if not (d and d.dir == "owe" and d.s and d.s.split) then return false end
  local mine = first((d.s and d.s.char) or (UnitName and UnitName("player")) or "")
  local p = { who = first(d.who), amt = math.floor(d.amt or d.rest or 0), ref = farmRef(d.s) .. "~" .. tostring(mine or ""), t = C.Now(), kind = "dsp" }
  for _, q in ipairs(fdb().pending) do if q.kind == "dsp" and q.who == p.who and q.ref == p.ref then
      sendForgive(q)
      C.Print(q.got and string.format("%s's Kina already has your dispute: it waits for them to answer.", tostring(p.who))
        or string.format("sent the dispute to %s again. If they're offline it goes out when you're online together (or through the guild), or by mail from any mailbox after 10 minutes.", tostring(p.who)))
      return true
    end end
  table.insert(fdb().pending, p)
  sendForgive(p)
  if C.Log then C.Log("dispute", "debt", p.who, p.amt, p.ref) end
  if C.After then C.After(60, function()
    for _, q in ipairs(fdb().pending) do
      if q == p and not q.got then
        C.Print(string.format("|cffffc54a%s's Kina hasn't answered yet|r (offline?). Kina keeps trying whenever you're grouped or both online in the guild, and from any mailbox after 10 minutes you can send it by mail.", tostring(p.who)))
      end
    end
  end) end
  C.Print(string.format("asked %s to clear the %s debt (%s). Their Kina asks them; you'll see the answer here.", C.Books and C.Books.Name(d.who) or d.who, C.Money(p.amt), d.farm or "farm"))
  return true
end
function C.AskDispute(d)
  if not d then return end
  C.ShowPopup("KINA_DISPUTE_ASK", string.format("Dispute the %s you owe %s?\n\nUse this when it was already paid or forgiven but Kina still shows it. %s's Kina asks them to clear it; if they do, any standing you lost for it comes back.",
    C.Money(math.floor(d.amt or 0)), C.Books and C.Books.Name(d.who) or d.who, C.Books and C.Books.Name(d.who) or d.who), nil, d)
end
C.Dialogs["KINA_DISPUTE_ASK"] = {
  text = "%s", button1 = "Dispute", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnAccept = function(_, d) if d then C.DisputeDebt(d) end end,
}
-- the one owed: someone disputes what they owe me
function C.OnDispute(from, amt, ref)
  from = first(from)
  C.SendReceipt(from, "dsp", ref)
  local base, theirChar = splitRef(ref)
  theirChar = (theirChar and theirChar ~= "") and first(theirChar) or nil
  local a = asks()
  a[askKey(from, ref)] = { from = from, amt = math.floor(amt or 0), ref = ref, t = C.Now() }
  for _, s in ipairs(C.db.sessions or {}) do
    if s.split and s.split.transfers and farmRef(s) == base then
      for _, t in ipairs(s.split.transfers) do
        if (t.to == "you" or isMine(t.to)) and (first(t.from) == from or (theirChar and first(t.from) == theirChar)) then
          local sp = s.split
          local done = (sp.received and sp.received[t.from] == true) or (sp.forgiven and sp.forgiven[t.from])
          if done then
            -- already closed here: tell their Kina again
            answered(from, ref)
            if C.Share and C.Share.SendForgive then pcall(C.Share.SendForgive, from, math.floor(t.amt or 0), ref) end
            return "resent"
          end
          C.ShowPopup("KINA_DISPUTE_DEBT", string.format("|cffffc54aDebt dispute|r\n\n%s disputes the %s they owe you from %s: they say it was already paid or forgiven.\n\nConfirm to clear the debt on both sides. Decline if it's still owed.",
            C.Books and C.Books.Name(from) or from, C.Money(math.floor(t.amt or 0)), s.label or "a farm"), nil, { s = s, t = t, from = from, ref = ref })
          return "asked"
        end
      end
    end
  end
  -- 1.0.3b (Taylor: she owes me on her side, but my Kina has no record of it): ask
  C.ShowPopup("KINA_DISPUTE_UNKNOWN", string.format("|cffffc54aDebt dispute|r\n\n%s's Kina says they owe you %s from a farm your Kina has no record of (it may have been played on another PC or character).\n\nConfirm to clear it on their side. Decline if it's still owed.",
    C.Books and C.Books.Name(from) or from, C.Money(math.floor(amt or 0))), nil, { from = from, ref = ref, amt = math.floor(amt or 0) })
  return "asked-unknown"
end
C.Dialogs["KINA_DISPUTE_UNKNOWN"] = {
  text = "%s", button1 = "Confirm dispute", button2 = "Decline", timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
  OnAccept = function(_, data)
    if not data then return end
    if C.Log then C.Log("forgive", "gave", data.from, data.amt, data.ref) end
    answered(data.from, data.ref)
    local p = { who = data.from, amt = data.amt, ref = data.ref, t = C.Now() }
    table.insert(fdb().pending, p); sendForgive(p)
    if C.Share and C.Share.SendForgiveAck then pcall(C.Share.SendForgiveAck, data.from, data.ref, "dsp") end
    C.Print(string.format("|cff7CFC00cleared|r %s's debt to you.", data.from))
  end,
  OnCancel = function(_, data)
    if not data then return end
    answered(data.from, data.ref)
    local p = { who = data.from, amt = 0, ref = data.ref, t = C.Now(), kind = "dsn" }
    table.insert(fdb().pending, p); sendForgive(p)
    C.Print(string.format("declined %s's dispute: the debt stays.", tostring(data.from)))
  end,
}
C.Dialogs["KINA_DISPUTE_DEBT"] = {
  text = "%s", button1 = "Confirm dispute", button2 = "Decline", timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
  OnAccept = function(_, data)
    if not data then return end
    local sp = data.s.split
    local key = data.t.from
    local left = math.floor(data.t.amt or 0)
    if type(sp.paid) == "table" and type(sp.paid[key]) == "number" then left = left - sp.paid[key] end
    sp.received = sp.received or {}; sp.received[key] = true
    sp.forgiven = sp.forgiven or {}; sp.forgiven[key] = math.max(0, left)
    if C.Log then C.Log("forgive", "gave", data.from, math.max(0, left), data.ref) end
    answered(data.from, data.ref)
    local p = { who = data.from, amt = math.max(0, left), ref = data.ref, t = C.Now() }
    table.insert(fdb().pending, p); sendForgive(p)
    if C.Share and C.Share.SendForgiveAck then pcall(C.Share.SendForgiveAck, data.from, data.ref, "dsp") end
    C.Print(string.format("|cff7CFC00cleared|r %s's debt (%s).", data.from, data.s.label or "farm"))
    if C.Refresh then pcall(C.Refresh) end
  end,
  OnCancel = function(_, data)
    if not data then return end
    answered(data.from, data.ref)
    local p = { who = data.from, amt = 0, ref = data.ref, t = C.Now(), kind = "dsn" }
    table.insert(fdb().pending, p); sendForgive(p)
    C.Print(string.format("declined %s's dispute: the debt stays.", tostring(data.from)))
  end,
}
-- the one who owes: the answer "it's still owed"
function C.OnDisputeDenied(from, ref)
  C.SendReceipt(from, "dsn", ref)
  C.OnForgiveAck(from, ref, "dsp")
  C.Print(string.format("|cffffc54a%s says the debt is still owed|r: pay it from the Ledger, or talk it over with them.", C.Books and C.Books.Name(from) or from))
end
function C.OnForgiveAck(from, ref, kind)
  local keep = {}
  for _, p in ipairs(fdb().pending) do if not (p.who == first(from) and p.ref == ref and (p.kind or "fgv") == (kind or "fgv")) then keep[#keep + 1] = p end end
  fdb().pending = keep
end

------------------------------------------------------------------ due dates, more time (1.1.1)
-- A debt is due 7 days after its farm; the debtor can ask once for more time, and the
-- person owed can give 3 more days (or forgive). Nothing happens automatically when a
-- debt is overdue yet: it just says so (standing comes later).
-- 1.2.6 (Taylor, Nov 5): parties with randoms settle fast. A debt is due 2 hours after
-- its farm ends; one extension adds 2 hours (4 hours at most). The clock never pauses.
-- (EXTEND_DAYS keeps its old name for older callers; it now counts HOURS.)
C.DEBT_HOURS, C.EXTEND_HOURS, C.MAX_HOURS = 2, 2, 4
C.DEBT_DAYS, C.EXTEND_DAYS = C.DEBT_HOURS, C.EXTEND_HOURS
-- 1.5.4 (Taylor): the debt clock counts PLAY time, not real time: it only runs while
-- the debtor or the creditor is logged in (2 hours of that, up to 4 with extensions).
-- Each Kina counts its own online time (sp.clock) and they swap counts when they meet
-- (sp.pclock); while both are online only the creditor's Kina counts, so the time isn't
-- counted twice. After a payment is offered and turned down there are 5 minutes in
-- which it can still be paid without anyone losing standing.
C.GRACE = 300
C.LATE_PAY = 0.8 -- 0.9.2 (Taylor): paying a debt after it ran out earns 80% of the XP and standing
function C.DebtLimit(d)
  local sp = d.s.split or {}
  local ext = sp.ext and tonumber(sp.ext[d.key]) or 0
  return math.min(C.MAX_HOURS, C.DEBT_HOURS + math.max(0, ext)) * 3600
end
function C.DebtUsed(d)
  local sp = d.s.split or {}
  return (sp.clock and sp.clock[d.key] or 0) + (sp.pclock and sp.pclock[d.key] or 0)
end
function C.DebtDue(d)
  if not (d and d.s) then return nil end
  local sp = d.s.split or {}
  local due = C.Now() + math.max(0, C.DebtLimit(d) - C.DebtUsed(d))
  local off = (d.dir == "owe" and sp.offered and sp.offered[d.key]) or (d.dir == "owed" and sp.refusedSeen and sp.refusedSeen[d.key])
  if tonumber(off) then due = math.max(due, off + C.GRACE) end
  return due
end
function C.DueText(d)
  local due = C.DebtDue(d)
  if not due then return "" end
  local left = due - C.Now()
  if left <= 0 then return "|cffff4040past due|r" end
  local h, m = math.floor(left / 3600), math.floor((left % 3600) / 60)
  return "due in " .. (h > 0 and (h .. " h " .. m .. " min") or (math.max(1, m) .. " min")) .. " of play"
end
-- run the clocks (every 30 s from Toast's debt check)
function C.TickDebtClocks()
  local now = C.Now()
  for _, d in ipairs(C.Debts()) do
    if d.s and not d.topup and d.amt >= 1 then
      local sp = d.s.split or {}; d.s.split = sp
      sp.clock = sp.clock or {}; sp.clockAt = sp.clockAt or {}
      local last = sp.clockAt[d.key]
      local together = C.InGroupName and C.InGroupName(d.who)
      if last and now - last > 0 and now - last <= 120 and (d.dir == "owed" or not together) then
        sp.clock[d.key] = (sp.clock[d.key] or 0) + (now - last)
      end
      sp.clockAt[d.key] = now
      if together and C.Share and C.Share.SendClock then
        pcall(C.Share.SendClock, d.who, math.floor(sp.clock[d.key] or 0), (d.s.sync and d.s.sync.sid) or ("t" .. tostring(d.s.start or 0)))
      end
    end
  end
end
-- their Kina told mine how long it has counted on our debt
function C.OnDebtClock(from, secs, ref)
  local who = first(from)
  for _, d in ipairs(C.Debts()) do
    if d.s and first(d.who) == who and (((d.s.sync and d.s.sync.sid) or ("t" .. tostring(d.s.start or 0))) == ref) then
      local sp = d.s.split or {}; d.s.split = sp
      sp.pclock = sp.pclock or {}
      -- 0.9.1 (security): their count can't run faster than the real clock (since the
      -- farm ended, and since their last count), so a made-up number can't make a
      -- debt past due on the spot
      sp.pclockAt = sp.pclockAt or {}
      local n = tonumber(secs) or 0
      local prev, prevAt = sp.pclock[d.key] or 0, sp.pclockAt[d.key]
      n = math.min(n, math.max(0, C.Now() - (d.s.stop or C.Now())))
      if prevAt then n = math.min(n, prev + (C.Now() - prevAt) + 60) end
      if n > prev then sp.pclock[d.key] = n end
      sp.pclockAt[d.key] = C.Now()
    end
  end
end
-- how much of the payment XP a payment earns by how soon it came after the farm:
-- full within 5 minutes, falling evenly to half at 1 hour, half after that
-- 1.0.2 (Taylor: "EXP and rep still isn't normalized between the creditor and the debtor
-- ... when you owe money to people you get significantly more rep than they do because
-- you are having to pay multiple people"): one rule for both sides of a payment.
--   * paying and being paid earn the SAME Kina XP and the same standing for that debt;
--   * a farm's award is shared over the debts you have in it: with debts to (or from)
--     three people, each payment is a third. Settling everything in a farm earns one full
--     award, however many payments it took and whichever side of them you were on.
-- (Awards are logged when a payment is confirmed, so older payments keep what they got.)
function C.DebtLinks(s, who)
  local me = first(who or (UnitName and UnitName("player")) or "")
  local mine = first((UnitName and UnitName("player")) or "")
  local n = 0
  for _, t in ipairs(s and s.split and s.split.transfers or {}) do
    if (tonumber(t.amt) or 0) > 0 then
      local f = (t.from == "you") and mine or first(t.from)
      local to = (t.to == "you") and mine or first(t.to)
      if f == me or to == me then n = n + 1 end
    end
  end
  return math.max(1, n)
end
function C.DebtXP(s, total, part, stop, late, who, at)
  local base = (C.Rep and C.Rep.PayXP and C.Rep.PayXP(total) or 0) * (part or 1) * C.PaySpeed(stop, at) * (late and C.LATE_PAY or 1)
  return base / C.DebtLinks(s, who)
end
function C.PaySpeed(stop, at)
  local t = (at or C.Now()) - (stop or at or 0)
  if t <= 300 then return 1 end
  if t >= 3600 then return 0.5 end
  return 1 - 0.5 * (t - 300) / 3300
end
local function queue(kind, who, amt, ref)
  local p = { kind = kind, who = first(who), amt = math.floor(amt or 0), ref = ref, t = C.Now() }
  table.insert(fdb().pending, p)
  sendForgive(p)
end
-- the debtor asks for more time (once per debt)
function C.AskForTime(d)
  if not (d and d.dir == "owe" and d.s and d.s.split) then return false end
  local sp = d.s.split
  sp.plea = sp.plea or {}
  if sp.plea[d.key] then C.Print("you already asked " .. C.Books.Name(d.who) .. " for more time on this one."); return false end
  sp.plea[d.key] = true
  if C.Log then C.Log("plea", "asked", d.who, math.floor(d.amt), farmRef(d.s)) end
  queue("plea", d.who, d.amt, farmRef(d.s))
  C.Print(string.format("asked %s for more time to pay %s (%s). They can give you %d more hours or forgive it.", C.Books.Name(d.who), C.Money(math.floor(d.amt)), d.farm or "farm", C.EXTEND_HOURS))
  if C.Refresh then C.Refresh() end
  return true
end
-- the person owed gives the debtor more time
function C.ExtendDebt(d)
  if not (d and d.dir == "owed" and d.s and d.s.split) then return false end
  local sp = d.s.split
  sp.ext = sp.ext or {}
  if (tonumber(sp.ext[d.key]) or 0) >= C.MAX_HOURS - C.DEBT_HOURS then C.Print("this debt already has the most time it can get (" .. C.MAX_HOURS .. " hours)."); return false end
  sp.ext[d.key] = (tonumber(sp.ext[d.key]) or 0) + C.EXTEND_HOURS
  if sp.pleaFrom then sp.pleaFrom[d.key] = nil end
  if C.Log then C.Log("extend", "gave", d.who, C.EXTEND_DAYS, farmRef(d.s)) end
  queue("ext", d.who, C.EXTEND_DAYS, farmRef(d.s))
  C.Print(string.format("gave %s %d more hours to pay %s.", C.Books.Name(d.who), C.EXTEND_HOURS, C.Money(math.floor(d.amt))))
  if C.Refresh then C.Refresh() end
  return true
end
-- from their Kina: a plea (we're owed) or an extension (we owe)
function C.OnDebtNote(kind, from, amt, ref)
  from = first(from)
  C.SendReceipt(from, kind, ref)
  for _, d in ipairs(C.Debts()) do
    if not d.topup and first(d.who) == from and d.s and farmRef(d.s) == ref then
      local sp = d.s.split
      if kind == "plea" and d.dir == "owed" then
        sp.pleaFrom = sp.pleaFrom or {}; sp.pleaFrom[d.key] = true
        C.Print(string.format("|cffffc54a%s asks for more time|r to pay the %s from %s. Open Kina > Ledger > Debts to give %d more hours or forgive it.",
          C.Books.Name(from), C.Money(math.floor(d.amt)), d.farm or "farm", C.EXTEND_DAYS))
      elseif kind == "ext" and d.dir == "owe" then
        sp.ext = sp.ext or {}; sp.ext[d.key] = math.min(C.MAX_HOURS - C.DEBT_HOURS, (tonumber(sp.ext[d.key]) or 0) + math.min(C.EXTEND_HOURS, tonumber(amt) or C.EXTEND_HOURS))
        C.Print(string.format("|cff7CFC00%s gave you %d more hours|r to pay the %s from %s.", C.Books.Name(from), tonumber(amt) or C.EXTEND_DAYS, C.Money(math.floor(d.amt)), d.farm or "farm"))
      end
      break
    end
  end
  if C.Share and C.Share.SendForgiveAck then pcall(C.Share.SendForgiveAck, from, ref, kind) end
  if C.Refresh then C.Refresh() end
end
-- re-send what hasn't been answered (they were offline or out of the group)
function C.ResendForgive()
  local keep = {}
  for _, p in ipairs(fdb().pending) do
    if C.Now() - (p.t or 0) < 30 * 86400 then
      keep[#keep + 1] = p; sendForgive(p)
      -- 1.0.5: not answered after 2 minutes and they aren't reachable: the guild carries it
      -- (again every 30 minutes)
      if not p.got and C.Now() - (p.t or 0) > 120 and (not p.couriered or C.Now() - p.couriered > 1800)
        and not (C.CanWhisper and C.CanWhisper(p.who)) and C.Share and C.Share.Courier then
        pcall(C.Share.Courier, p)
      end
    end
  end
  fdb().pending = keep
end
C.On("GROUP_ROSTER_UPDATE", function() if C.db and C.db.forgive and #C.db.forgive.pending > 0 then C.After(5, C.ResendForgive) end end)
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(300, function() if C.db and C.db.forgive and #(C.db.forgive.pending or {}) > 0 then pcall(C.ResendForgive) end end)
end
C.On("INIT", function() C.After(20, function() if C.db.forgive and #C.db.forgive.pending > 0 then C.ResendForgive() end end) end)
-- 1.0.5: a dispute I haven't answered yet asks again after login (30 days at most)
C.On("INIT", function() C.After(25, function()
  for k, q in pairs(asks()) do
    if C.Now() - (q.t or 0) > 30 * 86400 then asks()[k] = nil else pcall(C.OnDispute, q.from, q.amt, q.ref) end
  end
end) end)

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
      -- 0.9.2 (Taylor): a debt paid after it ran out earns 80% of the XP and standing
      local late = d.s and d.s.split and ((d.s.split.lapsed and d.s.split.lapsed[d.key]) or (C.DebtDue and C.DebtDue(d) and C.Now() > C.DebtDue(d))) and true or nil
      if d.dir == "owe" and gave - usedGave >= 1 then
        k = math.min(d.amt, gave - usedGave); markPaid(d, k); usedGave = usedGave + k
      elseif d.dir == "owed" and got - usedGot >= 1 then
        k = math.min(d.amt, got - usedGot); markPaid(d, k); usedGot = usedGot + k
      end
      if k > 0 then covers[#covers + 1] = { start = d.s and d.s.start, label = d.farm, amt = math.floor(k), dir = d.dir, topup = d.topup or nil, late = late,
        total = math.floor((d.tr and tonumber(d.tr.amt)) or (d.amt + 0)), stop = d.s and d.s.stop or nil } end
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
      if C.Now() - pc.t < (pc.mail and 259200 or 600) and not (first(pc.from) == who and not rec.conf and C._matchConf(rec, pc.gave, pc.label)) then keep[#keep + 1] = pc end
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
    -- 1.0.10: a payment that only covered farms with someone under level 10 gives no XP
    local nx = (#(r.covers or {}) > 0)
    for _, cv in ipairs(r.covers or {}) do
      local farm
      for _, s in ipairs(C.db.sessions or {}) do if cv.start and s.start == cv.start then farm = s; break end end
      if not (farm and farm.minLvl and farm.minLvl > 0 and farm.minLvl < (C.PROG_MIN_LEVEL or 10)) then nx = false end
    end
    -- 1.2.3: XP is set by the whole debt's size; a part payment earns its share of
    -- that, rounded down (paying 1c of a 23s debt earns 0)
    local payXP, recvXP, payRep = 0, 0, 0
    local function onTime(cv) return cv.stop and (r.t or C.Now()) <= cv.stop + C.DEBT_HOURS * 3600 end
    local function farmOf(cv)
      for _, s in ipairs(C.db.sessions or {}) do if cv.start and s.start == cv.start then return s end end
    end
    -- 1.0.2: the same XP and standing for both sides, shared over my debts in that farm
    for _, cv in ipairs(r.covers or {}) do
      local tot = math.max(tonumber(cv.total) or cv.amt or 0, cv.amt or 0)
      if tot >= 1 then
        local farm = farmOf(cv)
        local k = C.DebtLinks(farm)
        local part = (cv.amt or 0) / tot
        local lf = cv.late and C.LATE_PAY or 1
        if C.Rep and C.Rep.PayRep then
          payRep = payRep + (C.Rep.PayRep(tot) * part + (onTime(cv) and not cv.late and (cv.amt or 0) >= tot - 1 and C.Rep.EARLY_REP or 0)) * lf / k
        end
        local xp = C.DebtXP(farm, tot, part, cv.stop, cv.late, nil, r.t)
        if cv.dir == "owe" then payXP = payXP + xp else recvXP = recvXP + xp end
      end
    end
    if nx then payRep = 0 end
    if C.Log then C.Log("confirmed", via, r.who, r.gave, r.got, r.paidOff, r.cameIn, nx and "nx" or "", math.floor(payXP), math.floor(recvXP), math.floor(payRep)) end
    -- 1.2.6: the fanfare: what I earned and what they earned (the mirror of my covers)
    if C.Toast and C.Toast.Payment then
      local theirs, theirRep = 0, 0
      for _, cv in ipairs(r.covers or {}) do
        local total = math.max(tonumber(cv.total) or cv.amt or 0, cv.amt or 0)
        if total >= 1 then
          local farm = farmOf(cv)
          local part = (cv.amt or 0) / total
          local lf = cv.late and C.LATE_PAY or 1
          theirs = theirs + C.DebtXP(farm, total, part, cv.stop, cv.late, r.who, r.t)
          theirRep = theirRep + (C.Rep.PayRep(total) * part + (onTime(cv) and not cv.late and (cv.amt or 0) >= total - 1 and C.Rep.EARLY_REP or 0)) * lf / C.DebtLinks(farm, r.who)
        end
      end
      if nx then payXP, recvXP, theirs, theirRep = 0, 0, 0, 0 end
      pcall(C.Toast.Payment, r, math.floor(payXP + recvXP), math.floor(theirs), math.floor(payRep), math.floor(theirRep))
    end
    return true
  end
end
-- 1.2.6: a mail payment is sent and collected hours apart (and the other person may be
-- offline), so mail records match for 3 days, and each side re-sends what it saw
-- whenever that person shows up in the group again
local MAIL_WINDOW = 259200
function C.OnSettleConfirm(from, theirGave, label)
  local isMail = tostring(label or ""):match("^mail:") and true or false
  for _, r in ipairs(C.db.settles or {}) do
    local age = C.Now() - r.t
    if age > (isMail and MAIL_WINDOW or 600) then break end
    if first(r.who) == first(from) and not r.conf and (r.via == "mail") == isMail and C._matchConf(r, theirGave, label) then return true end
  end
  -- not seen yet (their message came first): keep it a while
  C.pendingConf = C.pendingConf or {}
  table.insert(C.pendingConf, { from = from, gave = theirGave, label = label, t = C.Now(), mail = isMail or nil })
end
local resent = {}
function C.ResendMailConfirms(who)
  if not (C.Share and C.Share.SendSettle) then return end
  who = first(who)
  for _, r in ipairs(C.db.settles or {}) do
    if C.Now() - r.t > MAIL_WINDOW then break end
    if r.via == "mail" and not r.conf and first(r.who) == who and (r.gave > 0 or r.got > 0) then
      local key = who .. (r.t or 0)
      if not resent[key] or C.Now() - resent[key] > 600 then
        resent[key] = C.Now()
        pcall(C.Share.SendSettle, "cnf", r.who, r.gave, "mail:" .. math.floor(r.got))
      end
    end
  end
end
local function plainMoney(c) return (C.Money(c):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- 1.0.2 (Taylor: mail "sometimes says enter a character's full name"): the mailbox wants
-- a plain "Name" for someone on your own realm and "Name-Realm" (no spaces) for another
-- realm. Kina's saved names can be a display name with a surname or carry your own
-- realm, and the mailbox refused those.
local function mailName(who)
  local full = (C.GroupMemberName and C.GroupMemberName(who)) or tostring(who or "")
  local name, realm = full:match("^%s*([^%s%-]+)[^%-]*%-?(.*)$")
  if not name or name == "" then return nil end
  realm = (realm or ""):gsub("%s", "")
  local mine = ((GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""):gsub("%s", "")
  if realm == "" or realm:lower() == mine:lower() then return name end
  return name .. "-" .. realm
end
C._MailName = mailName
-- 1.0.5 (Taylor: "please use the character's full name" mailing "Mr Bowjangles"): on WoW
-- Forever some players must be mailed by their first word ("Vellaura"), others by the whole
-- name ("Mr Bowjangles"). Kina tries the name that worked last time, then the first word,
-- then the whole name; when the game rejects one, the next is tried.
local function wholeName(who)
  local full = (C.GroupMemberName and C.GroupMemberName(who)) or tostring(who or "")
  local name, realm = full:match("^%s*([^%-]-)%s*%-(.*)$")
  if not name then name, realm = full:match("^%s*(.-)%s*$"), "" end
  name = (name or ""):gsub("%s+", " ")
  if name == "" then return nil end
  local mine = ((GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""):gsub("%s", "")
  realm = (realm or ""):gsub("%s", "")
  if realm == "" or realm:lower() == mine:lower() then return name end
  return name .. "-" .. realm
end
local function mailNames(who)
  local out, seen = {}, {}
  local function add(n) if n and n ~= "" and not seen[n:lower()] then seen[n:lower()] = true; out[#out + 1] = n end end
  local known = C.db.mailAs and C.db.mailAs[first(who) or ""]
  add(known); add(mailName(who)); add(wholeName(who))
  return out
end
C._MailNames = mailNames
local function rememberName(who, to)
  C.db.mailAs = C.db.mailAs or {}
  if first(who) then C.db.mailAs[first(who)] = to end
end

local queue, sending = {}, nil
local function sendNext()
  sending = table.remove(queue, 1)
  if not sending then if C.RefreshSettle then C.RefreshSettle() end; return end
  local d = sending
  d.names = d.names or mailNames(d.who)
  d.try = (d.try or 0) + 1
  local to = d.names[d.try]
  d.to = to
  if not to then
    C.Print("|cffff8040can't mail " .. tostring(d.who) .. "|r: Kina doesn't have a usable character name for them.")
    sending = nil; return sendNext()
  end
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
  if d.to then rememberName(d.who, d.to) end
  if d.dir == "owe" then C.SettleMoved(d.who, math.floor(d.amt), 0, "mail")
  else C.Print("asked " .. d.who .. " to settle (mail sent).") ; d.asked = true end
  C.After(0.6, sendNext)
end)
C.On("MAIL_FAILED", function()
  -- the game didn't take that name: try their other spelling before giving up
  if sending and sending.names and sending.try < #sending.names then
    local d = sending
    table.insert(queue, 1, d)
    C.After(0.5, sendNext)
    return
  end
  if sending then C.Print("|cffff8040mail to " .. sending.who .. " failed|r (Kina tried " .. table.concat(sending.names or {}, " and ") .. "). The rest were not sent.") end
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
      row.text:SetText(string.format("%s  |cffffc54a%s|r  %s  %s  %s", when, d.who, d.farm,
        d.dir == "owe" and "|cffff8080you owe|r" or "|cff7CFC00owes you|r", C.Money(d.amt)))
    else row.d = nil; row.cb:Hide(); row.text:Hide(); row.cb:SetChecked(false) end
  end
  sf.empty:SetText(#debts == 0 and "Nobody owes anybody. Nice." or "")
  local notes = C.MailableNotes and C.MailableNotes() or {}
  if sf.notes then
    if #notes > 0 then
      local who = {}
      for _, p in ipairs(notes) do who[#who + 1] = tostring(p.who) end
      sf.notes:SetText(string.format("|cffffc54a%d Kina note%s waiting|r for %s: they haven't been online with you. Press Mail notes to send them by mail.",
        #notes, #notes == 1 and "" or "s", table.concat(who, ", ")))
      sf.mailNotes:Show()
    else sf.notes:SetText(""); sf.mailNotes:Hide() end
  end
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
    local send = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(send) end
    send:SetSize(140, 22); send:SetPoint("BOTTOMLEFT", 10, 10); send:SetText("Send selected")
    send:SetScript("OnClick", function()
      queue = {}
      for _, row in ipairs(f.rows) do if row.d and row.cb:GetChecked() then queue[#queue + 1] = row.d; row.cb:SetChecked(false) end end
      if #queue == 0 then C.Print("tick who to settle with first."); return end
      sendNext()
    end)
    if C.ButtonTip then C.ButtonTip(send, "Send selected", "Mails the money you owe to everyone ticked (postage applies), and a request to everyone ticked who owes you. Paid debts drop off this list.") end
    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(all) end
    all:SetSize(110, 22); all:SetPoint("LEFT", send, "RIGHT", 6, 0); all:SetText("Tick all")
    all:SetScript("OnClick", function() for _, row in ipairs(f.rows) do if row.d then row.cb:SetChecked(true) end end end)
    if C.ButtonTip then C.ButtonTip(all, "Tick all", "Selects every row, so one Send settles everything.") end
    -- 1.0.5: notes that couldn't be delivered in game
    f.notes = C.Text(f, "OVERLAY", "GameFontHighlightSmall"); f.notes:SetPoint("BOTTOMLEFT", 12, 40); f.notes:SetWidth(400); f.notes:SetJustifyH("LEFT")
    local mn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(mn) end
    mn:SetSize(120, 22); mn:SetPoint("LEFT", all, "RIGHT", 6, 0); mn:SetText("Mail notes")
    mn:SetScript("OnClick", function() C.MailNotes() end)
    if C.ButtonTip then C.ButtonTip(mn, "Mail notes", "Forgiveness, disputes and requests Kina couldn't deliver because you weren't online together go out as short letters (normal postage). Their Kina reads them at their mailbox.") end
    f.mailNotes = mn
    sf = f
  end
  sf:ClearAllPoints()
  if MailFrame and MailFrame:IsShown() then sf:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0) else sf:SetPoint("CENTER") end
  sf:Show(); C.RefreshSettle()
end
-- 1.0.5 (Taylor: "build mail backup for sure, that's our catch-all"): notes Kina couldn't
-- deliver because the two of you weren't online together (a forgiveness, a dispute, a
-- plea for time) can go by mail. At the mailbox Kina lists them; YOU press "Mail notes"
-- (Kina never sends mail by itself). Each is a real letter (normal postage) with a short
-- code; the other player's Kina reads it when they open their mailbox and acts on it.
local NOTE_SUBJ = "Kina note"
local NOTE_KINDS = { fgv = true, dsp = true, plea = true, ext = true, dsn = true, fga = true, dsa = true }
local NOTE_TEXT = {
  fgv = "I forgave what you owed me from %s.", dsp = "I'm disputing the %s debt from %s: it was already paid or forgiven.",
  plea = "Could I have a bit more time to pay the %s from %s?", ext = "I gave you more time to pay the %s from %s.",
}
function C.MailableNotes()
  local out = {}
  for _, p in ipairs(fdb().pending) do
    local k = p.kind or "fgv"
    if NOTE_KINDS[k] and not p.mailed and not p.got and C.Now() - (p.t or 0) >= 600 then out[#out + 1] = p end
  end
  return out
end
local function noteBody(p)
  local k = p.kind or "fgv"
  local farm = p.label
  if not farm then
    for _, s in ipairs(C.db.sessions or {}) do if farmRef(s) == p.ref then farm = s.label end end
  end
  farm = farm or "a farm"
  local line = k == "fgv" and string.format(NOTE_TEXT.fgv, farm) or string.format(NOTE_TEXT[k] or "", C.Money(p.amt or 0), farm)
  -- the code: no "|" (the game reads it as an escape), so ":" and "#"
  return line .. "\n\n(Kina reads this for you: [kina#" .. k .. "#" .. math.floor(p.amt or 0) .. "#" .. tostring(p.ref or "") .. "])"
end
local noteQueue, noteSending = {}, nil
local function noteNext()
  noteSending = table.remove(noteQueue, 1)
  if not noteSending then if C.RefreshSettle then C.RefreshSettle() end; return end
  noteSending.names = noteSending.names or C._MailNames(noteSending.who)
  noteSending.try = (noteSending.try or 0) + 1
  local to = noteSending.names[noteSending.try]
  noteSending.to = to
  if not to then noteSending = nil; return noteNext() end
  if SetSendMailMoney then SetSendMailMoney(0) end
  SendMail(to, NOTE_SUBJ, noteBody(noteSending))
end
function C.MailNotes(list)
  if not (SendMail and MailFrame and MailFrame:IsShown()) then C.Print("open a mailbox first."); return end
  noteQueue = {}
  for _, p in ipairs(list or C.MailableNotes()) do noteQueue[#noteQueue + 1] = p end
  if #noteQueue == 0 then C.Print("no notes waiting."); return end
  noteNext()
end
C.On("MAIL_SEND_SUCCESS", function()
  local p = noteSending
  if not p then return end
  p.mailed = C.Now()
  if p.to then C.db.mailAs = C.db.mailAs or {}; C.db.mailAs[C.FirstName and C.FirstName(p.who) or p.who] = p.to end
  p.names, p.try, p.to = nil, nil, nil
  C.Print(string.format("mailed a Kina note to %s.", p.who))
  noteSending = nil
  C.After(0.6, noteNext)
end)
C.On("MAIL_FAILED", function()
  if noteSending and noteSending.names and noteSending.try < #noteSending.names then
    table.insert(noteQueue, 1, noteSending); noteSending = nil
    C.After(0.5, noteNext); return
  end
  if noteSending then C.Print("|cffff8040the Kina note to " .. noteSending.who .. " couldn't be mailed|r (wrong name or realm?).") end
  if noteSending then noteSending.names, noteSending.try, noteSending.to = nil, nil, nil end
  noteSending = nil; noteQueue = {}
end)
-- reading notes: once per letter (remembered), only Kina's own subject
function C.ReadNote(sender, body)
  local k, amt, ref = tostring(body or ""):match("%[kina#(%a+)#(%-?%d+)#([^%]]*)%]")
  if not k or not NOTE_KINDS[k] then return false end
  amt = tonumber(amt) or 0
  if k == "fgv" and C.OnForgiven then C.OnForgiven(sender, amt, ref)
  elseif k == "dsp" and C.OnDispute then C.OnDispute(sender, amt, ref)
  elseif k == "dsn" and C.OnDisputeDenied then C.OnDisputeDenied(sender, ref)
  elseif (k == "fga" or k == "dsa") and C.OnForgiveAck then C.OnForgiveAck(sender, ref, k == "dsa" and "dsp" or nil)
  elseif (k == "plea" or k == "ext") and C.OnDebtNote then C.OnDebtNote(k, sender, amt, ref) end
  return true
end
C.On("MAIL_INBOX_UPDATE", function()
  if not (GetInboxNumItems and GetInboxHeaderInfo and GetInboxText) then return end
  C.db.seenMail = C.db.seenMail or {}
  local seen = C.db.seenMail
  for i = 1, GetInboxNumItems() do
    local _, _, sender, subject, _, _, daysLeft = GetInboxHeaderInfo(i)
    if sender and subject == NOTE_SUBJ then
      -- remembered by its content (the days left on a letter change as time passes)
      local ok, body = pcall(GetInboxText, i)
      local code = ok and body and tostring(body):match("%[kina#[^%]]*%]")
      local key = code and ("note|" .. sender .. "|" .. code)
      if key and not seen[key] then
        seen[key] = C.Now()
        pcall(C.ReadNote, sender, body)
      end
    end
  end
end)
-- the mailbox opens: show it when there is something to settle or a note to mail
C.On("MAIL_SHOW", function()
  C.After(0.3, function()
    if #C.Debts() > 0 or #C.MailableNotes() > 0 then C.ShowSettle() end
    -- 1.0.5: say it plainly: notes that couldn't be delivered can go now (only on your click)
    local n = #C.MailableNotes()
    if n > 0 then
      local who = {}
      for _, q in ipairs(C.MailableNotes()) do who[#who + 1] = tostring(q.who) end
      C.ShowPopup("KINA_MAIL_NOTES", string.format("|cffffc54aKina notes waiting|r\n\n%d note%s (disputes, answers, forgiveness) couldn't reach %s because you weren't online together.\n\nSend %s by mail now? Normal postage (30c each). Their Kina reads it when they open their mailbox.",
        n, n == 1 and "" or "s", table.concat(who, ", "), n == 1 and "it" or "them"))
    end
  end)
end)
C.On("MAIL_CLOSED", function() if sf then sf:Hide() end; if C.HidePopup then pcall(C.HidePopup, "KINA_MAIL_NOTES") end end)
C.Dialogs["KINA_MAIL_NOTES"] = {
  text = "%s", button1 = "Mail them", button2 = "Not now", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnAccept = function() C.MailNotes() end,
}
