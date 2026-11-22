-- Kina: FarmSync. Connects the shared farm log (SyncCore.lua) to the game: who is in
-- the farm, what each player reports, the invite popup, and what the widget shows.
local _, C = ...
local Core = C.SyncCore
local F = {}
C.FarmSync = F

local node
local function first(n) return type(n) == "string" and not (issecretvalue and issecretvalue(n)) and n:match("^%s*([^%s%-]+)") or nil end
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
-- 1.0.2 (Taylor: "what happens when I join a group that already has a Kina farm going and
-- I start another one? The widgets should be synced to let me know they are in a farm"):
-- the leader's Kina repeats its invite once a minute for the whole farm, so someone who
-- joins the group later hears about it. Kina remembers the group's running farm: the
-- widget says whose farm is running, and Start joins it (it never starts a second one).
local known
function F.Running()
  local k = known
  if not k or C.Now() - k.t > 150 then return nil end
  if not unitOf(k.leader) then return nil end
  if C.TrackOnly and C.TrackOnly() then return nil end
  local s = C.session
  if s and s.sync and s.sync.sid == k.sid then return nil end
  return k
end
-- 1.0.7 (Taylor): while your group's farm runs, Start never makes a second farm. If you
-- said no to it, Start asks whether to join it now; otherwise it joins.
function F.JoinRunning()
  local k = F.Running()
  if not k then return false end
  if declined[k.sid] then
    if C.Dialogs and StaticPopup_Show then
      C.Dialogs["KINA_FARM_DECLINED"] = C.Dialogs["KINA_FARM_DECLINED"] or {
        text = "%s's group farm is still running, and you said no to it.\n\nYou can't start your own farm until it ends. Join it now?",
        button1 = "Join", button2 = "Not now", timeout = 60, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function(_, d) if d then declined[d.sid] = nil; F.Accept(d.sid, d.leader, d.label or "", d.camp or "") end end,
      }
      C.ShowPopup("KINA_FARM_DECLINED", k.leader, nil, k)
    end
    return true
  end
  F.Accept(k.sid, k.leader, k.label or "", k.camp or "")
  return true
end
-- 1.0.7: a farm started by a Kina that hadn't seen the group's other Kinas yet (no
-- shared log): asked, never started for you
local soloAsked = {}
function F.AskSolo(from, label, camp)
  local who = first(from) or from
  if soloAsked[who] and C.Now() - soloAsked[who] < 600 then return end
  soloAsked[who] = C.Now()
  if not (C.Dialogs and StaticPopup_Show) then return end
  C.Dialogs["KINA_FARM_SOLO"] = C.Dialogs["KINA_FARM_SOLO"] or {
    text = "%s started a farm: %s\n\nJoin it? If you say no, Kina tracks nothing for you until it ends.",
    button1 = "Join", button2 = "No thanks", timeout = 120, whileDead = true, hideOnEscape = false, preferredIndex = 3,
    OnAccept = function(_, d) if d and not C.session then C.StartSession(d.label ~= "" and d.label or nil, true, d.camp ~= "" and d.camp or nil) end end,
  }
  C.ShowPopup("KINA_FARM_SOLO", who, (label and label ~= "") and label or "farm", { label = label or "", camp = camp or "" })
end
-- 1.0.7: who said yes or no to a farm (the farm's starter shows it in the roster)
F.answers = {}   -- [sid] = { [name] = "no" }
function F.OnDecline(from, sid)
  local who = first(from)
  if not (who and sid and sid ~= "") then return end
  F.answers[sid] = F.answers[sid] or {}
  F.answers[sid][who] = "no"
  if F.RefreshRoster then pcall(F.RefreshRoster) end
end
F.declined = declined
local function onInvite(sid, leader, label, camp)
  if C.TrackOnly and C.TrackOnly() then return end -- 0.9.20: tracker only: no group farms
  if C.session and C.session.sync and C.session.sync.sid == sid then return end
  if not unitOf(leader) then return end -- only from someone in your group
  known = { sid = sid, leader = leader, label = label, camp = camp, t = C.Now() }
  if C.RefreshWidget and not C.session then pcall(C.RefreshWidget) end
  if declined[sid] then return end
  -- (1.0.7, Taylor: nobody is put in a farm without saying yes: no auto-join)
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
  if not (C.Dialogs and StaticPopup_Show) then return end
  C.Dialogs["KINA_FARM_INVITE"] = C.Dialogs["KINA_FARM_INVITE"] or {
    text = "%s's group farm is running: %s\n\nJoin it? Everyone's widget shows the same numbers and Kina splits the loot fairly.\nIf you say no, Kina tracks nothing for you until it ends.",
    button1 = "Join", button2 = "No thanks",
    timeout = 120, whileDead = true, hideOnEscape = false, preferredIndex = 3,
    OnAccept = function(_, d) F.Accept(d.sid, d.leader, d.label, d.camp) end,
    OnCancel = function(_, d, why)
      if not d or why == "timeout" then return end -- no answer: still a "?"
      declined[d.sid] = true
      if C.Share and C.Share.SendFarmCmd then pcall(C.Share.SendFarmCmd, "decline", d.sid) end
      -- declining the shared farm also ends a farm the group's start command opened
      -- for you, so you are not counted in one split while the group uses another
      local cs = C.session
      if cs and cs.byParty and not cs.sync and C.Now() - (cs.start or 0) < 600 then
        C.session = nil; C.db.activeSession = nil
        C.Print("you're not in " .. tostring(d.leader) .. "'s farm.")
        if C.OnSessionChange then C.OnSessionChange() end
      end
    end,
  }
  C.ShowPopup("KINA_FARM_INVITE", leader, (label and label ~= "") and label or "farm",
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
      inGroup = function(name) return unitOf(name) ~= nil end,
      present = function(name) -- 1.0.2b: in the group and online
        local u = unitOf(name)
        return u ~= nil and not (UnitIsConnected and UnitIsConnected(u) == false)
      end,
      onForged = function()
        local s = C.session
        if s and not s.forgedSaid then
          s.forgedSaid = true
          C.Print("|cffff4030Kina found loot in this farm's log under your name that you never looted.|r Your Kina won't record debts from this farm's split.")
          if C.Share and C.Share.SendTamper then pcall(C.Share.SendTamper, s.label) end
        end
      end,
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
  C.Print("group farm started: Kina users in your group get an invite to join." .. (C.settings.farmNoSplit and " |cffffc54aNo split:|r numbers are shared, nobody owes anything." or ""))
  if F.ShowRoster then pcall(F.ShowRoster) end
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
    elseif s.sync then
      -- 1.0.8: you're joining a new group farm: the old shared one closes on your side now,
      -- with the shared numbers (waiting on its leader could keep you out of the new one)
      C.StopSession(nil, "joined another farm", nil, true)
    else C.StopSession() end
    if C.session then C.session = nil; C.db.activeSession = nil end
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
function F.Excluded(s) return Core.Excluded(s) end

-- What the widget shows for a shared farm: straight from the log.
function F.View()
  local s = C.session and C.session.sync
  if not (s and node and node.s == s) then return nil end
  local t = Core.Totals(s)
  return { secs = node:Elapsed(), net = t.net, coin = t.coin, items = t.items, used = t.used, kills = t.kills,
    paused = t.paused, byLooter = t.byLooter, heldBy = t.heldBy, members = t.members, noSplit = t.noSplit,
    behind = (s.leaderHead or 0) > s.head or next(s.outbox) ~= nil }, s.leader
end
function F.Totals(s, reprice) return Core.Totals(s, reprice) end
function F.Split(by) return Core.Split(by) end

-- the clock
local ticker = CreateFrame("Frame")
local acc = 0
C.GuardScript(ticker, "OnUpdate", "FarmSync:223", function(_, dt)
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


------------------------------------------------------------------ the farm roster
-- 1.0.7 (Taylor): pressing Start shows every Kina user in the group with a green check
-- (in the farm), a red X (said no) or a yellow question mark (hasn't answered yet). It
-- updates as they answer. Any farmer can end the farm for everyone from here.
local roster
local READY, NOTREADY, WAITING = "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady", "Interface\\RaidFrame\\ReadyCheck-Waiting"
-- who's who: { name, state = "yes" | "no" | "wait" }, you first
-- 2.0 (Taylor: warn when a group member's Kina is too old to join your farm): the version
-- each group member's Kina last said it runs (from its hello)
local function vnum(v)
  local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)")
  return a and (tonumber(a) * 1e6 + tonumber(b) * 1e3 + tonumber(c)) or 0
end
function F.KinaVersionOf(name)
  local want = (tostring(name or ""):match("^([^%s%-]+)") or ""):lower()
  local sh = C.db and C.db.share
  if want == "" or not (sh and sh.authors) then return nil end
  local best, bestT
  for _, a in pairs(sh.authors) do
    local hit = a.name and (a.name:match("^([^%s%-]+)") or a.name):lower() == want
    if not hit and a.chars then for n in pairs(a.chars) do if (n:match("^([^%s%-]+)") or n):lower() == want then hit = true end end end
    if hit and a.ver and (not bestT or (a.seen or a.t or 0) > bestT) then best, bestT = a.ver, a.seen or a.t or 0 end
  end
  return best
end
function F.TooOld(name)
  local v = F.KinaVersionOf(name)
  return v and vnum(v) < vnum(C.version) and v or nil
end
function F.RosterList()
  local s = C.session and C.session.sync
  local sid = s and s.sid
  local inFarm, said = {}, {}
  for n in pairs((node and s and node.s == s) and node:members() or {}) do inFarm[n:lower()] = true end
  for n, v in pairs(sid and F.answers[sid] or {}) do said[n:lower()] = v end
  -- names as the game shows them (Kina's lists keep some in lower case)
  local proper = {}
  local mine = me()
  proper[mine:lower()] = mine
  if IsInGroup and IsInGroup() then
    local raid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, raid and n or (n - 1) do
      local u = raid and ("raid" .. i) or ("party" .. i)
      local nm = UnitExists and UnitExists(u) and first(UnitName(u))
      if nm then proper[nm:lower()] = nm end
    end
  end
  local out, seen = {}, {}
  local function add(k)
    k = k:lower()
    if seen[k] or k == "" then return end
    seen[k] = true
    local st = (k == mine:lower() or inFarm[k]) and "yes" or (said[k] == "no" and "no" or "wait")
    local old = st == "wait" and F.TooOld(k) or nil
    if old then st = "old" end
    out[#out + 1] = { name = proper[k] or (k:sub(1, 1):upper() .. k:sub(2)), state = st, ver = old }
  end
  add(mine)
  local names = {}
  for n in pairs(C.FarmMates and C.FarmMates() or {}) do names[#names + 1] = n:lower() end
  for n in pairs(inFarm) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do add(n) end
  return out
end
local function buildRoster()
  local f = CreateFrame("Frame", "KinaFarmRoster", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(300, 140); f:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(120); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
  f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.95); f:SetBackdropBorderColor(0.94, 0.58, 0.03, 1)
  end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOP", 0, -12)
  if C.Cos and C.Cos.Font then C.Cos.Font(f.title, 18, "OUTLINE") end
  f.title:SetText("Group farm"); f.title:SetTextColor(1, 0.79, 0.36)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -3)
  f.rows = {}
  f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(f.close) end
  f.close:SetSize(100, 22); f.close:SetPoint("BOTTOMRIGHT", -14, 12); f.close:SetText("Close")
  f.close:SetScript("OnClick", function() f:Hide() end)
  f.stop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(f.stop) end
  f.stop:SetSize(120, 22); f.stop:SetPoint("BOTTOMLEFT", 14, 12); f.stop:SetText("End farm for all")
  f.stop:SetScript("OnClick", function() if C.session then C.StopSession() end; f:Hide() end)
  f.key = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.key:SetPoint("BOTTOM", 0, 40)
  f.key:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t in   |TInterface\\RaidFrame\\ReadyCheck-NotReady:12|t said no   |TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t no answer yet")
  f:Hide()
  return f
end
function F.RefreshRoster()
  if not (roster and roster:IsShown()) then return end
  if not (C.session and C.session.sync) then roster:Hide(); return end
  local list = F.RosterList()
  roster.sub:SetText(C.session.label or "")
  for i, e in ipairs(list) do
    local r = roster.rows[i]
    if not r then
      r = CreateFrame("Frame", nil, roster); r:SetSize(260, 22)
      r.icon = r:CreateTexture(nil, "OVERLAY"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0)
      r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
      r.state = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.state:SetPoint("RIGHT", -4, 0)
      roster.rows[i] = r
    end
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 20, -54 - (i - 1) * 24)
    r.icon:SetTexture(e.state == "yes" and READY or ((e.state == "no" or e.state == "old") and NOTREADY or WAITING))
    r.name:SetText(e.name .. (e.name == me() and " |cff9d9d9d(you)|r" or ""))
    r.state:SetText(e.state == "yes" and "|cff3fd03fin the farm|r" or (e.state == "no" and "|cffff5050said no|r")
      or (e.state == "old" and ("|cffff8040old Kina (v" .. e.ver .. "): needs an update|r")) or "|cffffd040no answer yet|r")
    -- tell you once per farm, in your chat only
    if e.state == "old" then
      roster.warned = roster.warned or {}
      local key = (C.session.sync.sid or "") .. e.name
      if not roster.warned[key] then
        roster.warned[key] = true
        C.Print(e.name .. "'s Kina is too old (v" .. e.ver .. ") to join your farm. They need to update Kina to v" .. tostring(C.version) .. ".")
      end
    end
    r.entry = e
    r:Show()
  end
  for i = #list + 1, #roster.rows do roster.rows[i]:Hide() end
  roster:SetHeight(54 + #list * 24 + 64)
  -- 1.0.8 (Taylor: "why is there End farm for all while waiting for her reply"): until
  -- someone else is in, it's your farm alone, so the button just cancels it
  local others = 0
  for _, e in ipairs(list) do if e.state == "yes" and e.name ~= me() then others = others + 1 end end
  if roster.stop then roster.stop:SetText(others > 0 and "End farm for all" or "Cancel farm") end
end
function F.ShowRoster()
  roster = roster or buildRoster()
  roster:Show(); roster:Raise()
  F.RefreshRoster()
end
F.RosterShown = function() return roster ~= nil and roster:IsShown() end
local rt = CreateFrame("Frame")
local racc = 0
rt:SetScript("OnUpdate", function(_, dt)
  racc = racc + dt
  if racc < 1 then return end
  racc = 0
  if roster and roster:IsShown() then pcall(F.RefreshRoster) end
end)
