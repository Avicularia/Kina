-- Kina: playing in a group.
--   * group size and who is in it (per-kill values are split across the group)
--   * gold per hour from YOUR timed farms only, matched to who you're with now:
--       same people > same classes > same group size with other classes
--   * farm settlement: at the end of a group farm every Kina tells the group what it
--     gathered (coin, pickpockets, vendor sales, loot at full price: no AH cut or
--     deposits) and Kina works out who pays whom so everyone ends up even
--   * sync: when a Kina user joins your group, one click sets them up as your partner
local _, C = ...

------------------------------------------------------------------ who is here
-- Is this player in your party or raid? Works across realms: "Vellaura",
-- "Vellaura-ClassicBetaPvE" and "Vellaura-Classic Beta PvE" all match.
-- WoW Forever's addon messages name the sender by display name ("Vellaura Mistwalker",
-- surname and no realm) while UnitName says "Vellaura": match on the first name.
local function firstName(n) return ((n or ""):match("^%s*([^%s%-]+)") or ""):lower() end
C.FirstName = firstName
-- The group member a sender name means, as "Name-Realm" (for whispers), or nil.
function C.GroupMemberName(name)
  if not name or not (IsInGroup and IsInGroup()) then return nil end
  local want = firstName(name)
  if want == "" then return nil end
  local raid = IsInRaid and IsInRaid()
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, raid and n or (n - 1) do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    if UnitExists and UnitExists(unit) then
      local nm, realm = UnitName(unit)
      if nm and firstName(nm) == want then
        return nm .. "-" .. ((realm and realm ~= "" and realm or (GetRealmName and GetRealmName() or "")):gsub("%s", ""))
      end
    end
  end
  return nil
end
function C.InGroupName(name)
  return C.GroupMemberName(name) ~= nil
end

-- Who shares a group farm: you, plus group members who run Kina (seen in the last 30
-- minutes). Strangers in a dungeon group are never part of the farm or its split.
function C.FarmMates()
  local set, n = {}, 1
  set[firstName(UnitName and UnitName("player") or "")] = true
  local S = C.Share
  for _, a in pairs(S and S.DB and S.DB().authors or {}) do
    if a.name and a.seen and C.Now() - a.seen < 1800 and C.InGroupName(a.name) then
      local k = firstName(a.name)
      if k ~= "" and not set[k] then set[k] = true; n = n + 1 end
    end
  end
  return set, n
end
function C.IsFarmMate(name) return (C.FarmMates())[firstName(name)] == true end

function C.GroupSize()
  if IsInRaid and IsInRaid() then return math.max(1, GetNumGroupMembers and GetNumGroupMembers() or 1) end
  if IsInGroup and IsInGroup() then return math.max(1, GetNumGroupMembers and GetNumGroupMembers() or 1) end
  return 1
end

local function short(name) return name and (name:match("^([^%-]+)") or name) or "?" end

-- Everyone in your group except you: { {name = "Vellaura", class = "DRUID"} }, sorted
function C.GroupMates()
  local out = {}
  if not (IsInGroup and IsInGroup()) then return out end
  local raid = IsInRaid and IsInRaid()
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, raid and n or (n - 1) do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    if UnitExists and UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
      local cls = UnitClass and select(2, UnitClass(unit))
      out[#out + 1] = { name = short(UnitName(unit)), class = cls or "?" }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function key(list, field)
  local t = {}
  for _, m in ipairs(list or {}) do t[#t + 1] = m[field] or "?" end
  table.sort(t)
  return table.concat(t, ",")
end
local function nice(cls) return cls and (cls:sub(1, 1) .. cls:sub(2):lower()) or "?" end
local function names(list)
  local t = {}
  for _, m in ipairs(list or {}) do t[#t + 1] = m.name end
  return table.concat(t, ", ")
end
local function classes(list)
  local t = {}
  for _, m in ipairs(list or {}) do t[#t + 1] = nice(m.class) end
  return table.concat(t, ", ")
end

------------------------------------------------------------------ group farm leader
-- Among the Kina users in your group, the one whose name sorts first counts the
-- group's farm for everybody: the others show its numbers, so all widgets agree.
function C.FarmLeader()
  if not (C.GroupSize and C.GroupSize() > 1) then return nil, true end
  local me = UnitName("player")
  local best = me
  local S = C.Share
  local now = C.Now()
  for _, a in pairs(S and S.DB and S.DB().authors or {}) do
    local nm = a.name and (a.name:match("^([^%-]+)") or a.name)
    if nm and a.seen and now - a.seen < 900 and C.InGroupName(a.name) and nm:lower() < best:lower() then best = nm end
  end
  return best, best == me
end

------------------------------------------------------------------ measured rates
-- Gold per hour per person for a mob, from your timed farms where it was at least
-- half the kills (5+ minutes). Only the farms that match who you're with now count,
-- best match first. nil = never farmed in a matching group (the tab shows 0).
function C.MeasuredRate(npc)
  if not npc then return nil end
  local mates = C.GroupMates()
  local nowNames, nowClasses = key(mates, "name"), key(mates, "class")
  local tiers = {}
  for _, s in ipairs(C.db.sessions or {}) do
    local k = s.byNpc and s.byNpc[npc]
    if s.result and k and (s.kills or 0) > 0 and k / s.kills >= 0.5 and (s.result.secs or 0) >= 300 then
      local party = s.party or {}
      if #party == #mates then
        local tier
        if key(party, "name") == nowNames then tier = 1
        elseif key(party, "class") == nowClasses then tier = 2
        else tier = 3 end
        local t = tiers[tier]
        if not t then t = { income = 0, secs = 0, n = 0, party = party }; tiers[tier] = t end
        -- your share: the even split when the group's numbers came in, else what you made
        t.income = t.income + ((s.split and s.split.each) or s.result.total or 0)
        t.secs = t.secs + s.result.secs
        t.n = t.n + 1
      end
    end
  end
  for tier = 1, 3 do
    local t = tiers[tier]
    if t and t.secs > 0 then
      local label
      if #mates == 0 then label = "your solo farms"
      elseif tier == 1 then label = "with " .. names(t.party)
      elseif tier == 2 then label = "with another " .. classes(t.party) .. " (" .. names(t.party) .. ")"
      else label = "with other classes (" .. classes(t.party) .. ": " .. names(t.party) .. ")" end
      return { rate = t.income * 3600 / t.secs, n = t.n, label = label, tier = tier, hours = t.secs / 3600 }
    end
  end
end

------------------------------------------------------------------ settlement
-- What a farm session gathered, for splitting: coin, pickpockets, vendor sales and
-- other income, plus looted items at their full price (no AH cut, no deposits).
-- Money spent (repairs, food) is not part of the split.
function C.FarmIncome(s)
  local m = s.money or {}
  local cash = (m.coin or 0) + (m.pickpocket or 0) + (m.vendor or 0) + (m.other or 0)
  local items = 0
  for id, n in pairs(s.items or {}) do
    -- the Farms tab's price (safe price on thin markets), before the AH cut
    local v, route = C.FarmValue(id)
    local each = v or 0
    if route == "AUCTION" or route == "SELL" then each = each / (1 - (C.settings.ahCut or 0.05)) end
    items = items + each * n
  end
  return math.floor(cash + items + 0.5)
end

-- incomes = { name = copper } (you included as "you"): even split and transfers
local function settle(incomes)
  local total, n = 0, 0
  for _, v in pairs(incomes) do total = total + v; n = n + 1 end
  local each = n > 0 and total / n or 0
  local pay, get = {}, {}
  for who, v in pairs(incomes) do
    local d = v - each
    if d > 0.5 then pay[#pay + 1] = { who = who, amt = d } elseif d < -0.5 then get[#get + 1] = { who = who, amt = -d } end
  end
  table.sort(pay, function(a, b) return a.amt > b.amt end)
  table.sort(get, function(a, b) return a.amt > b.amt end)
  local transfers, i, j = {}, 1, 1
  while pay[i] and get[j] do
    local amt = math.min(pay[i].amt, get[j].amt)
    transfers[#transfers + 1] = { from = pay[i].who, to = get[j].who, amt = math.floor(amt + 0.5) }
    pay[i].amt = pay[i].amt - amt; get[j].amt = get[j].amt - amt
    if pay[i].amt <= 0.5 then i = i + 1 end
    if get[j].amt <= 0.5 then j = j + 1 end
  end
  return total, each, transfers
end

C.Settle = settle

-- The group farm's split from the loot lines (what each player looted, at the farm
-- leader's prices; coin is left out because the game already splits it).
-- s.gsplit = { by = { name = copper }, from = leader }. Prints it and keeps s.split.
function C.ShowGroupSplit(s)
  if not (s and s.gsplit and s.gsplit.by) or s.gsplitShown then return end
  local by = {}
  for who, v in pairs(s.gsplit.by) do by[who] = v end
  local everyone = {}
  for _, m in ipairs(s.party or {}) do everyone[#everyone + 1] = m end
  everyone[#everyone + 1] = { name = UnitName and UnitName("player") or "you" } -- you too, even with nothing looted
  for _, m in ipairs(everyone) do
    local have = false
    for who in pairs(by) do if C.FirstName(who) == C.FirstName(m.name) then have = true end end
    if not have then by[m.name] = 0 end
  end
  local n = 0
  for _ in pairs(by) do n = n + 1 end
  if n < 2 then return end
  local total, each, transfers = settle(by)
  s.split = { total = total, each = each, incomes = by, transfers = transfers, loot = true }
  s.settled, s.gsplitShown = true, true
  C.Print(string.format("|cffffc54aFarm split|r (%s): the group looted %s, %s each (%s's prices; coin is already split by the game).",
    s.label or "farm", C.Money(total), C.Money(each), tostring(s.gsplit.from or "leader")))
  -- (each person's figure has their consumables taken out: admin view only)
  if C.Admin() then for who, v in pairs(by) do C.Print(string.format("   %s looted %s", who, C.Money(v))) end end
  if #transfers == 0 then C.Print("   Everyone is even: nobody owes anything.") end
  for _, t in ipairs(transfers) do C.Print(string.format("   |cff7CFC00%s pays %s %s|r", t.from, t.to, C.Money(t.amt))) end
  if C.RefreshWidget then C.RefreshWidget() end
end
-- the leader's split arrived (from Share.lua)
function C.OnGroupSplit(by, from)
  -- 0.9.1 (security): only the group's farm leader sends the split
  local leader = C.FarmLeader and C.FarmLeader()
  if not (leader and tostring(from):lower():match("^[^%-]+") == tostring(leader):lower():match("^[^%-]+")) then return end
  local g = { by = by, from = from }
  local s = C.session
  if s and s.g then C.pendingSplit = { t = C.Now(), g = g }; return end -- Stop hasn't reached us yet
  s = C.db.sessions and C.db.sessions[1]
  if s and s.g and s.stop and C.Now() - s.stop < 1800 then
    if s.gsplit and (s.gsplit.mine or s.gsplitShown) then return end -- ours, or already shown (copies)
    s.gsplit = g; s.gsplitShown = nil
    C.ShowGroupSplit(s)
  end
end

-- Prints the split once every member's numbers are in.
function C.TrySettle(s)
  if not (s and s.party and #s.party > 0 and s.myIncome) or s.settled then return end
  local incomes = { you = s.myIncome }
  for _, m in ipairs(s.party) do
    local v = s.partners and s.partners[m.name]
    if not v then return end -- still waiting for someone
    incomes[m.name] = v
  end
  local total, each, transfers = settle(incomes)
  s.split = { total = total, each = each, incomes = incomes, transfers = transfers }
  s.settled = true
  C.Print(string.format("|cffffc54aFarm split|r (%s): %d players gathered %s, %s each.", s.label or "farm", #s.party + 1, C.Money(total), C.Money(each)))
  for who, v in pairs(incomes) do C.Print(string.format("   %s gathered %s", who == "you" and "You" or who, C.Money(v))) end
  if #transfers == 0 then C.Print("   Everyone is even: nobody owes anything.") end
  for _, t in ipairs(transfers) do
    local from = t.from == "you" and "You pay" or (t.from .. " pays")
    C.Print(string.format("   |cff7CFC00%s %s %s|r", from, t.to == "you" and "you" or t.to, C.Money(t.amt)))
  end
end

-- A farm of yours ended: tell the group what you gathered, then settle if we can.
function C.FarmEnded(s)
  if not s or s.sync then return end -- a shared farm's split comes from its log (Loot.lua)
  local mates = C.GroupMates()
  -- everyone who was with you at the start or the end of the farm
  local seen, party = {}, {}
  -- only Kina users in the group share the farm (never strangers from a dungeon group)
  for _, m in ipairs(s.party or {}) do if not seen[m.name] and C.IsFarmMate(m.name) then seen[m.name] = true; party[#party + 1] = m end end
  for _, m in ipairs(mates) do if not seen[m.name] and C.IsFarmMate(m.name) then seen[m.name] = true; party[#party + 1] = m end end
  table.sort(party, function(a, b) return a.name < b.name end)
  s.party = party
  if #party == 0 then return end
  s.myIncome = C.FarmIncome(s)
  s.partners = s.partners or {}
  -- numbers that arrived before you stopped
  for _, m in ipairs(party) do
    local e = C.db.farmIn and C.db.farmIn[m.name]
    if e and math.abs((e.stop or 0) - (s.stop or 0)) < 3600 and (e.stop or 0) >= s.start then s.partners[m.name] = e.income end
  end
  if C.Share and C.Share.SendFarm then C.Share.SendFarm(s) end
  if s.g then
    -- group farm: split what everyone looted (same numbers for everyone, from the leader)
    if s.gsplit then C.ShowGroupSplit(s); if s.settled then return end end
    if C.pendingSplit and C.Now() - C.pendingSplit.t < 300 then s.gsplit = C.pendingSplit.g; C.pendingSplit = nil; C.ShowGroupSplit(s); return end
    C.Print("farm ended: waiting for the leader's Kina to send the split.")
    -- not here in a while: ask for it again
    if C.After and C.Share and C.Share.AskSplit then
      for _, d in ipairs({ 12, 40 }) do C.After(d, function() if not s.gsplitShown then C.Share.AskSplit() end end) end
    end
    return
  end
  C.TrySettle(s)
  if not s.settled then C.Print("farm ended: waiting for your group's numbers to split the gold (they arrive when they stop their farm).") end
end

-- A group member's farm ended (from Share.lua).
function C.OnPartnerFarm(name, start, stop, income)
  name = short(name)
  C.db.farmIn = C.db.farmIn or {}
  C.db.farmIn[name] = { start = start, stop = stop, income = income, t = C.Now() }
  -- their group farm ended but yours is still running (the Stop note got lost): end it too
  local cur = C.session
  if cur and cur.g and stop >= (cur.start or 0) and C.InGroupName and C.InGroupName(name) then
    C.StopSession(math.min(stop, C.Now()), "group stopped", false, true)
    return
  end
  for _, s in ipairs(C.db.sessions or {}) do
    if s.party and s.myIncome and not s.settled and math.abs((s.stop or 0) - stop) < 3600 then
      for _, m in ipairs(s.party) do
        if m.name == name then
          s.partners = s.partners or {}; s.partners[name] = income
          C.TrySettle(s)
          return
        end
      end
    end
  end
end

------------------------------------------------------------------ sync popup
-- A Kina user in your group said hello: offer to use them as your partner.
local asked, greeted = {}, {}
function C.ResetSyncAsks() wipe(asked) end
local function inGroup(name) return C.InGroupName(name) end
function C.OnKinaMate(name, char, tries)
  local full = name
  if C.ResendMailConfirms then pcall(C.ResendMailConfirms, name) end
  name = short(name)
  if asked[name] or not char or not char.class then return end
  if not inGroup(full) then
    -- the hello can beat the roster update: look again in a moment
    if (tries or 0) < 3 and C.After then C.After(3, function() C.OnKinaMate(full, char, (tries or 0) + 1) end) end
    return
  end
  asked[name] = true
  if not greeted[name] then
    greeted[name] = true
    C.Print(string.format("%s runs Kina: syncing scans, loot and community drop data (progress on the scan bar).", name))
  end
  -- 0.9.14 (Taylor): no more "Use them as your farming partner?" popup. It only fed the
  -- private build's farm planner (public Kina never showed it), and the split works
  -- through the farm invite either way. The chat line above is all that's left.
end
C.On("GROUP_ROSTER_UPDATE", function()
  -- ask again next time someone rejoins
  for name in pairs(asked) do
    if not C.InGroupName(name) then asked[name] = nil end
  end
  if C.Refresh then C.Refresh() end
end)
