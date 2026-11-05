-- Kina: FarmSync. Connects the shared farm log (SyncCore.lua) to the game: who is in
-- the farm, what each player reports, the invite popup, and what the widget shows.
local _, C = ...
local Core = C.SyncCore
local F = {}
C.FarmSync = F

local node
local function first(n) return type(n) == "string" and n:match("^%s*([^%s%-]+)") or nil end
F.First = first
local function me() return first(UnitName and UnitName("player")) or "?" end

-- the unit for a group member, by first name (nil = not in the group)
local function unitOf(name)
  if not (IsInGroup and IsInGroup()) then return nil end
  local raid = IsInRaid and IsInRaid()
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, raid and n or (n - 1) do
    local u = raid and ("raid" .. i) or ("party" .. i)
    if UnitExists and UnitExists(u) and first(UnitName(u)) == name then return u end
  end
end
-- the game says the leader is gone: left the group, or offline
local function leaderGone(name)
  if name == me() then return false end
  -- no group to look at (just logged in, or the roster isn't loaded yet): we can't
  -- tell, so we don't say gone (if the group really ended, the farm ends anyway)
  if not (IsInGroup and IsInGroup()) then return false end
  local u = unitOf(name)
  if not u then return true end
  if UnitIsConnected and UnitIsConnected(u) == false then return true end
  return false
end

local declined = {}
local function onInvite(sid, leader, label, camp)
  if declined[sid] then return end
  if C.session and C.session.sync and C.session.sync.sid == sid then return end
  if not unitOf(leader) then return end -- only from someone in your group
  local auto = C.settings.farmAutoJoin and C.settings.farmAutoJoin[leader]
  if auto then F.Accept(sid, leader, label, camp); return end
  -- your group's start command already started this farm for you (the leader's Kina
  -- hadn't heard from yours yet): it has become a shared farm, so you join it the same
  -- way you were put in it. Two different kinds of farm in one group would split
  -- differently, and the debts wouldn't match.
  local s = C.session
  if s and s.byParty and not s.sync and C.Now() - (s.start or 0) < 180 then
    C.Print(leader .. "'s farm is now a shared farm: joined it.")
    F.Accept(sid, leader, label, camp)
    return
  end
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs["KINA_FARM_INVITE"] = StaticPopupDialogs["KINA_FARM_INVITE"] or {
    text = "%s started a group farm: %s\n\nJoin it? Both widgets show the same numbers and Kina splits the loot fairly.",
    button1 = "Join", button2 = "Not now", button3 = "Always join",
    timeout = 120, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, d) F.Accept(d.sid, d.leader, d.label, d.camp) end,
    OnCancel = function(_, d)
      if not d then return end
      declined[d.sid] = true
      -- declining the shared farm also ends a farm the group's start command opened
      -- for you, so you are not counted in one split while the group uses another
      local cs = C.session
      if cs and cs.byParty and not cs.sync and C.Now() - (cs.start or 0) < 600 then
        C.session = nil; C.db.activeSession = nil
        C.Print("you're not in " .. tostring(d.leader) .. "'s farm.")
        if C.OnSessionChange then C.OnSessionChange() end
      end
    end,
    OnAlt = function(_, d)
      C.settings.farmAutoJoin = C.settings.farmAutoJoin or {}
      C.settings.farmAutoJoin[d.leader] = true
      F.Accept(d.sid, d.leader, d.label, d.camp)
    end,
  }
  StaticPopup_Show("KINA_FARM_INVITE", leader, (label and label ~= "") and label or "farm",
    { sid = sid, leader = leader, label = label, camp = camp })
end

local function finish()
  -- the log says the farm is over: end the local session with the log's numbers
  local s = C.session
  if s and s.sync and s.sync.closed and not s.syncEnded then
    s.syncEnded = true
    C.StopSession(nil, "group stopped", false, true)
  end
end

local function onChange()
  -- a pause pressed on any widget pauses everyone's
  local s = C.session
  if s and s.sync and node and node.s == s.sync then
    local p = Core.Totals(s.sync).paused and true or false
    if p ~= (s.paused and true or false) then
      if p then s.paused, s.pauseAt = true, C.Now()
      else s.pausedSecs = (s.pausedSecs or 0) + (C.Now() - (s.pauseAt or C.Now())); s.paused, s.pauseAt = nil, nil end
      C.Print(p and "group farm paused: nothing counts until someone resumes." or "group farm resumed.")
    end
  end
  if C.RefreshWidget then C.RefreshWidget() end
  finish()
end

function F.Node()
  if not node then
    node = Core.new({
      me = me(),
      now = function() return C.Now() end,
      send = function(msg, to) if C.Share and C.Share.SendSync then C.Share.SendSync(msg, to) end end,
      price = function(id, suffix) return C.SplitValue and (C.SplitValue(id, suffix)) or 0 end, -- the split price (thin greens at their floor)
      leaderGone = leaderGone,
      onInvite = onInvite,
      onChange = onChange,
    })
  end
  node.env.me = me()
  return node
end

-- Who else in the group runs Kina (seen in the last 30 minutes)?
function F.Mates()
  if not C.FarmMates then return 1 end
  local _, n = C.FarmMates()
  return n or 1
end

-- A farm you start: shared when someone in your group runs Kina, else solo.
function F.Begin(s, label, camp)
  if not (IsInGroup and IsInGroup()) or F.Mates() < 2 then return false end
  local n = F.Node()
  n:Start(label or s.label, camp)
  s.sync = n.s
  s.g = nil -- the shared log replaces the old group numbers
  -- 1.0.10: "don't split" goes into the log, so every widget and every split agrees
  if C.settings.farmNoSplit then n:Observe("N", "1") end
  C.Print("group farm started: Kina users in your group get an invite to join." .. (C.settings.farmNoSplit and " |cffffd100No split:|r numbers are shared, nobody owes anything." or ""))
  return true
end

-- A farm started a moment before Kina saw the other Kina users in the group (they
-- had only just joined): turn it into a shared farm instead of leaving it solo.
function F.Upgrade()
  local s = C.session
  if not s or s.sync or s.byParty or s.paused then return end
  if C.Now() - (s.start or 0) > 120 then return end
  if F.Begin(s, s.label, s.camp) and C.OnSessionChange then C.OnSessionChange() end
end

-- You accepted an invite.
function F.Accept(sid, leader, label, camp)
  local s = C.session
  -- already in this farm (a second Join click, a repeated invite): nothing to do.
  -- (Starting it again would stop it, and stopping a shared farm stops it for everyone.)
  if s and s.sync and s.sync.sid == sid then return end
  if s and not (s.sync and s.sync.sid == sid) then
    -- a young farm your group's start command opened is replaced, not saved as its own farm
    if s.byParty and not s.sync and C.Now() - (s.start or 0) < 180 then
      C.session = nil; C.db.activeSession = nil
    else C.StopSession() end
  end
  C.StartSession(label ~= "" and label or nil, true, camp ~= "" and camp or nil)
  local n = F.Node()
  n:Join(sid, leader)
  C.session.sync = n.s
  C.session.g = nil
  C.Print("joined " .. leader .. "'s group farm.")
end

-- Report something you did. kind/data as in SyncCore.
function F.Observe(kind, data)
  local s = C.session
  if not (s and s.sync and node and node.s == s.sync) then return end
  node:Observe(kind, data)
end
function F.Active() local s = C.session; return s and s.sync and node and node.s == s.sync and true or false end

function F.Receive(from, payload)
  -- the leader is stopping: our batched uses go out first
  if type(payload) == "string" and payload:sub(1, 2) == "T|" and C.FlushUse then pcall(C.FlushUse, true) end
  F.Node():Receive(first(from) or from, payload)
end

-- Leave out / count again one entry of the log (right-click in the farm log).
function F.ToggleEntry(seq)
  local s = C.session and C.session.sync
  if not s then return end
  local ex = false
  for _, ev in ipairs(s.chain) do
    if ev.kind == "E" then
      local q, on = ev.data:match("^(%d+):(%d)$")
      if tonumber(q) == seq then ex = (on == "1") end
    end
  end
  F.Observe("E", seq .. ":" .. (ex and "0" or "1"))
end
function F.Excluded(s)
  local ex = {}
  for _, ev in ipairs(s and s.chain or {}) do
    if ev.kind == "E" then
      local q, on = ev.data:match("^(%d+):(%d)$")
      if q then ex[tonumber(q)] = (on == "1") or nil end
    end
  end
  return ex
end

-- What the widget shows for a shared farm: straight from the log.
function F.View()
  local s = C.session and C.session.sync
  if not (s and node and node.s == s) then return nil end
  local t = Core.Totals(s)
  return { secs = node:Elapsed(), net = t.net, coin = t.coin, items = t.items, used = t.used, kills = t.kills,
    paused = t.paused, byLooter = t.byLooter, members = t.members, noSplit = t.noSplit,
    behind = (s.leaderHead or 0) > s.head or next(s.outbox) ~= nil }, s.leader
end
function F.Totals(s) return Core.Totals(s) end
function F.Split(by) return Core.Split(by) end

-- the clock
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  if acc < 1 then return end
  acc = 0
  -- (keeps running 3 minutes after the stop so a teammate who missed the end catches up)
  if node and node.s and ((C.session and C.session.sync == node.s) or (node.s.closed and C.Now() - (node.s.closedAt or C.Now()) < 190)) then
    local ok, err = pcall(node.Tick, node)
    if not ok and C.debug then C.Print("farm sync: " .. tostring(err)) end
  end
end)

-- after a reload: pick the shared farm back up
C.On("INIT", function()
  C.After(3, function()
    local s = C.session
    if s and s.sync and not s.sync.closed then
      local n = F.Node()
      n:Resume(s.sync)
      C.Print("group farm resumed: catching up with " .. tostring(s.sync.leader) .. ".")
    end
  end)
end)
