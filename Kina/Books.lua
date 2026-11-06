-- Kina: the books behind the public Ledger. Pure numbers (the UI only draws them):
--   * one row per farm: farmed, your share, collected, left to collect, paid, still owed, XP
--   * a farm's details: where the gold came from, the split, every debt and payment, XP
--   * gold flow: everything Kina saw come in and go out
--   * XP history (replayed from the event log) and XP still waiting for an action
-- Everything is "as seen by Kina": gold that moved while Kina wasn't watching isn't here.
local _, C = ...
local B = {}
C.Books = B

local function first(n) return C.FirstName and C.FirstName(n) or (n and tostring(n):match("^([^%s%-]+)")) end
local function me() return first(UnitName and UnitName("player")) end
local function isMe(n) return n == "you" or first(n) == me() end
-- how much of a transfer is done (the paid/received maps hold copper, or true when full)
local function done(map, key, amt)
  local v = map and map[key]
  if v == true then return amt end
  return math.min(amt, tonumber(v) or 0)
end
-- a name to show: no realm, first letter capital ("triforce-Forever" -> "Triforce")
function B.Name(n)
  n = tostring(n or "?"):match("^([^%-]+)") or "?"
  return n:sub(1, 1):upper() .. n:sub(2)
end
local function inPeriod(t, days) return not days or (t and C.Now() - t <= days * 86400) end

-- XP gains from the log, keyed to farms (by shared-farm id) and to payments
local function xpIndex()
  local gains = C.Rep and C.Rep.History and C.Rep.History() or {}
  local bySid = {}
  for _, g in ipairs(gains) do if g.sid and (g.kind == "farm" or (g.kind == "short" and g.why)) then bySid[g.sid] = g end end
  return gains, bySid
end
-- the XP gain that a payment record earned (matched on who, how and how much)
local function gainFor(rec, gains)
  for _, g in ipairs(gains) do
    if (g.kind == "pay" or g.kind == "receipt") and first(g.who) == first(rec.who) and g.via == rec.via
        and g.gave == math.floor(rec.gave + 0.5) and g.got == math.floor(rec.got + 0.5) and math.abs(g.t - (rec.conf or rec.t)) <= 900 then
      return g
    end
  end
end

-- One farm's numbers. s = a saved farm (C.db.sessions entry).
function B.Farm(s, gains, bySid)
  if not gains then gains, bySid = xpIndex() end
  local sp = s.split
  local r = { s = s, t = s.stop or s.start, label = s.label or "farm", secs = (s.result and s.result.secs) or ((s.stop or s.start) - s.start),
    farmed = 0, mine = 0, share = 0, collected = 0, toCollect = 0, paid = 0, owe = 0, xp = 0, debts = {}, players = 1 }
  if sp and sp.transfers then
    -- Farmed = the group's NET (coin + loot - consumables), the same number the widget shows.
    -- The game splits coin evenly by itself; Kina's split covers the loot. Your share of the
    -- farm is your coin from the game plus your loot share = NET / players.
    r.lootSplit, r.lootShare = sp.total or 0, sp.each or 0
    local n = 0
    for who, v in pairs(sp.incomes or {}) do n = n + 1; if isMe(who) then r.mine = v end end
    r.players = math.max(1, n)
    local gv = s.gview
    if gv and gv.net then
      r.farmed, r.groupCoin, r.groupItems, r.groupUsed = gv.net, gv.coin or 0, gv.items or 0, gv.used or 0
      r.coinShare = (gv.coin or 0) / r.players
      r.share = r.coinShare + r.lootShare
    elseif (r.lootSplit or 0) == 0 and s.result and (s.result.total or 0) ~= 0 then
      -- 1.0.10: a group farm that was never shared (the partner's numbers never came):
      -- show what you farmed instead of a row of dashes
      r.farmed, r.share, r.unshared = s.result.total, s.result.total, true
    else
      r.farmed, r.share = r.lootSplit, r.lootShare -- an old farm saved without the group's totals
    end
    r.open = false
    
    for _, t in ipairs(sp.transfers) do
      if t.amt and t.amt > 0 then
        if isMe(t.from) then
          local d = done(sp.paid, t.to, t.amt)
          r.paid, r.owe = r.paid + d, r.owe + (t.amt - d)
          r.debts[#r.debts + 1] = { dir = "owe", who = t.to, amt = t.amt, done = d }
        elseif isMe(t.to) then
          local d = done(sp.received, t.from, t.amt)
          r.collected, r.toCollect = r.collected + d, r.toCollect + (t.amt - d)
          r.debts[#r.debts + 1] = { dir = "owed", who = t.from, amt = t.amt, done = d }
        end
      end
    end
  else
    -- a solo farm: everything farmed is yours
    r.farmed = (s.result and s.result.total) or 0
    r.mine, r.share = r.farmed, r.farmed
  end
  for _, d in ipairs(r.debts) do if d.amt - d.done >= 1 then r.open = true end end
  -- XP: the farm itself, plus the payments that paid this farm's debts
  r.payments = {}
  local g = s.sync and s.sync.sid and bySid[s.sync.sid]
  if g and g.kind == "short" then r.shortWhy = g.why; g = nil end
  if g then r.farmXP = g.xp; r.farmGain = g; r.xp = r.xp + (g.xp or 0) end
  for _, rec in ipairs(C.db.settles or {}) do
    for _, cv in ipairs(rec.covers or {}) do
      if cv.start and cv.start == s.start then
        local pg = gainFor(rec, gains)
        -- a payment that covered several farms: its XP counts once, on the first one
        local firstFarm = rec.covers[1] == cv
        r.payments[#r.payments + 1] = { rec = rec, amt = cv.amt, dir = cv.dir, gain = pg, counted = firstFarm }
        if pg and firstFarm then r.xp = r.xp + (pg.xp or 0) end
      end
    end
  end
  return r
end

-- every farm in the period, newest first; and the totals
function B.Farms(days)
  local gains, bySid = xpIndex()
  local rows, tot = {}, { farmed = 0, mine = 0, collected = 0, toCollect = 0, paid = 0, owe = 0, xp = 0, n = 0 }
  for _, s in ipairs(C.db.sessions or {}) do
    if type(s) == "table" and s.start and inPeriod(s.stop or s.start, days) then
      local r = B.Farm(s, gains, bySid)
      -- 1.0.10: a farm where nothing happened (started and stopped at once) is left out
      local empty = (r.farmed or 0) == 0 and #r.debts == 0 and (r.xp or 0) == 0 and #r.payments == 0
      if not empty then rows[#rows + 1] = r end
      for _, k in ipairs({ "farmed", "mine", "collected", "toCollect", "paid", "owe", "xp" }) do tot[k] = tot[k] + (r[k] or 0) end
      tot.n = tot.n + 1
    end
  end
  -- sale top-ups (an item from a shared farm sold for more than the split counted)
  local owed = C.db.payout and C.db.payout.owed or {}
  for who, amt in pairs(owed) do if amt >= 1 then tot.owe = tot.owe + amt; tot.topups = (tot.topups or 0) + amt end end
  tot.waiting = 0
  for _, w in ipairs(B.Waiting()) do tot.waiting = tot.waiting + (w.xp or 0) end
  return rows, tot
end

-- XP still to be had, and what to do for it
function B.Waiting()
  local out = {}
  local R = C.Rep
  if not R then return out end
  local sharing = not C.ShareData or C.ShareData()
  for _, d in ipairs(C.Debts and C.Debts() or {}) do
    -- 1.2.3: XP follows the whole debt; what's left earns its share of it
    local total = math.max((d.tr and tonumber(d.tr.amt)) or d.amt, d.amt)
    local part = total >= 1 and d.amt / total or 1
    if d.dir == "owe" then
      out[#out + 1] = { xp = math.floor(R.PayXP(total) * part * (C.PaySpeed and C.PaySpeed(d.s and d.s.stop) or 1)), what = string.format("Pay %s %s", B.Name(d.who), C.Money(math.floor(d.amt))),
        why = d.topup and "AH sale top-up" or (d.farm or "farm"), kind = "pay", who = d.who, amt = d.amt }
    else
      out[#out + 1] = { xp = math.floor(R.RECV_XP * part), what = string.format("%s pays you %s", B.Name(d.who), C.Money(math.floor(d.amt))),
        why = d.farm or "farm", kind = "receipt", who = d.who, amt = d.amt }
    end
  end
  -- payments waiting for the other player's Kina to confirm them (10 minutes, then it's too late)
  for _, rec in ipairs(C.db.settles or {}) do
    if not rec.conf and C.Now() - (rec.t or 0) < 600 then
      local xp = (rec.paidOff or 0) >= 1 and R.PayXP(rec.paidOff) or ((rec.cameIn or 0) >= 1 and R.RECV_XP or 0)
      if xp > 0 then out[#out + 1] = { xp = xp, what = "Waiting for " .. B.Name(rec.who) .. "'s Kina to confirm", why = rec.via, kind = "confirm" } end
    end
  end
  if not sharing then
    for _, w in ipairs(out) do w.paused = true end
    out[#out + 1] = { xp = 0, what = "Turn data sharing on (Settings) to earn any of this", kind = "sharing" }
  end
  return out
end

-- Gold that came in and went out, by kind (as seen by Kina)
function B.Flow(days)
  local inn = { coin = 0, pickpocket = 0, items = 0, vendor = 0, ahSales = 0, received = 0 }
  local out = { paid = 0, ahCut = 0, used = 0, postage = 0 }
  for _, s in ipairs(C.db.sessions or {}) do
    if type(s) == "table" and s.start and inPeriod(s.stop or s.start, days) then
      local m, r = s.money or {}, s.result or {}
      inn.coin = inn.coin + (m.coin or 0)
      inn.pickpocket = inn.pickpocket + (m.pickpocket or 0)
      inn.vendor = inn.vendor + (m.vendor or 0)
      inn.items = inn.items + (r.items or 0)
      out.used = out.used + (r.used or 0)
    end
  end
  local led = C.db.ledger
  for _, e in ipairs(led and led.entries or {}) do
    if type(e) == "table" and e.kind == "sale" and inPeriod(e.t, days) then
      inn.ahSales = inn.ahSales + (e.net or 0)
      out.ahCut = out.ahCut + (e.cut or 0)
    end
  end
  for _, rec in ipairs(C.db.settles or {}) do
    if inPeriod(rec.t, days) then
      inn.received = inn.received + (rec.got or 0)
      out.paid = out.paid + (rec.gave or 0)
      if rec.via == "mail" and (rec.gave or 0) > 0 then out.postage = out.postage + 30 end
    end
  end
  return inn, out
end

-- 1.2.0: the You tab's record: farms, shares, payments, forgiveness, who you farmed with
function C.YouRecord()
  local me = UnitName and UnitName("player")
  local mine = me and (me:match("^([^%-]+)") or me)
  local function isMe(n) return n and mine and (tostring(n):match("^([^%-]+)") or n) == mine end
  local r = { farms = 0, hours = 0, share = 0, paid = 0, paidAmt = 0, recv = 0, recvAmt = 0, forgaveN = 0, forgivenN = 0, oweNow = 0, owedNow = 0 }
  local who, whoList = {}, {}
  local gains, bySid = C.Rep and C.Rep.History and C.Rep.History() or {}, {}
  for _, s in ipairs(C.db.sessions or {}) do
    if type(s) == "table" and s.start and s.sync then
      r.farms = r.farms + 1
      r.hours = r.hours + ((s.stop or s.start) - s.start - (s.pausedSecs or 0)) / 3600
      local ok, f = pcall(B.Farm, s, gains, bySid)
      if ok and f then r.share = r.share + (f.share or 0) end
      local sp = s.split or {}
      for _, t in ipairs(sp.transfers or {}) do
        if sp.forgiven and sp.forgiven[t.to] and isMe(t.from) then r.forgivenN = r.forgivenN + 1 end
        if sp.forgiven and sp.forgiven[t.from] and isMe(t.to) then r.forgaveN = r.forgaveN + 1 end
      end
      for n in pairs(sp.incomes or {}) do
        local nm = B.Name(n)
        if not isMe(n) and not who[nm] then who[nm] = true; whoList[#whoList + 1] = nm end
      end
    end
  end
  for _, rec in ipairs(C.db.settles or {}) do
    if rec.conf then
      if (rec.paidOff or 0) >= 1 then r.paid = r.paid + 1; r.paidAmt = r.paidAmt + rec.paidOff end
      if (rec.cameIn or 0) >= 1 then r.recv = r.recv + 1; r.recvAmt = r.recvAmt + rec.cameIn end
    end
  end
  for _, d in ipairs(C.Debts and C.Debts() or {}) do
    if d.dir == "owe" then r.oweNow = r.oweNow + d.amt else r.owedNow = r.owedNow + d.amt end
  end
  table.sort(whoList)
  if #whoList > 0 then r.partners = table.concat(whoList, ", ", 1, math.min(4, #whoList)) .. (#whoList > 4 and (" +" .. (#whoList - 4)) or "") end
  return r
end
