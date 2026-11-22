-- Kina network (1.0.6). Kina users anywhere in the realm, not only the guild or group:
--  * a hidden chat channel every Kina joins. Only invisible addon messages go over it;
--    nothing is ever said in it, and it's taken out of every chat window
--  * invisible addon messages straight to one character (never a chat whisper), only to
--    someone Kina has just heard from, so the game never answers "No player named..."
--  * the developer: Kina knows the developer's characters (Forever names are unique across
--    the region), and only trusts those names for what only the developer may say
-- Built for feedback first; the LFG system will ride on the same network.
local _, C = ...
local N = {}
C.Net = N
N.PREFIX = "KinaNet"
-- 2.0 (found Nov 21, live test with Rippy: both in KinaNetwork, neither heard the other):
-- the game hands an addon only the messages sent under prefixes it registered. Kina never
-- registered this one (1.0.7 to 2.0 betas), so no Kina ever heard another on the network.
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, N.PREFIX) end
N.CHANNEL = "KinaNetwork"
N.ONLINE_HOLD = 20 * 60   -- the developer counts as online this long after their last "online"
N.ANNOUNCE_EVERY = 15 * 60

-- the developer's characters (full names, as the game shows them)
N.DEVELOPERS = {
  "Deputize Deez",
  "Avic Hybana",
}

local function short(name)
  if type(name) ~= "string" then return "" end
  if Ambiguate then local ok, s = pcall(Ambiguate, name, "short"); if ok and s then name = s end end
  return (name:gsub("%-.*$", ""))
end
N.Short = short
-- the full name ("First Surname") must match; a bare first name (if the game ever gives
-- one without the surname) matches only that exact first name
function N.IsDeveloper(name)
  local s = short(name):lower()
  if s == "" then return false end
  for _, d in ipairs(N.DEVELOPERS) do
    d = d:lower()
    if d == s then return true end
    if not s:find(" ", 1, true) and d:match("^(%S+)") == s then return true end
  end
  return false
end
function N.Me() return (UnitName and UnitName("player")) or "?" end
-- 2.0: the game gives your first name, but others (and your own messages coming back) show
-- "First Surname". Learned from your own messages coming back over the channel.
N.meFull = nil
function N.MeFull() return N.meFull or N.Me() end
local sentRecently = {} -- [message] = when: to recognise your own coming back
local function isMe(from, msg)
  local f, me = from:lower(), N.Me():lower()
  if f == me or (N.meFull and f == N.meFull:lower()) then
    if msg and sentRecently[msg] then N.lastEcho = C.Now() end
    return true
  end
  if f:match("^(%S+)") == me and msg and sentRecently[msg] and C.Now() - sentRecently[msg] < 60 then
    N.meFull = from
    N.lastEcho = C.Now()
    return true
  end
  return false
end
N.IsMe = isMe
function N.IAmDeveloper() return N.IsDeveloper(N.Me()) end
function N.Enabled() return not (C.settings and C.settings.netOff) end

------------------------------------------------------------------ the channels
-- 2.0 (Taylor: "it has never found anyone on the network"). Found in how other WoW Forever
-- addons keep a realm-wide network: the game turns players away from a busy custom channel
-- (the notice NOT_ALLOWED_IN_CHANNEL), and the channel then sits in your list switched off,
-- every message to it refused, while it still looks joined. 1.0.9 saw a channel number and
-- thought it was in. Now:
--  * a ladder of channels: KinaNetwork, then KinaNetworkB to E. Every Kina tries them in
--    the same order, so a player turned away lands where the others turned away are
--  * a channel switched off (or locked: a password, a ban) counts as not joined, and Kina
--    moves to the next one; every 10 minutes the earlier ones are tried again, so players
--    gather back in the first as it has room
--  * relays (KinaRelay): one Kina on each channel also sits in the relay channel and passes
--    the network's notes between the channels, so Kinas on different channels still hear
--    each other (Relay, further on)
N.CHANNELS = { "KinaNetwork", "KinaNetworkB", "KinaNetworkC", "KinaNetworkD", "KinaNetworkE" }
N.RELAY = "KinaRelay"
N.current = 1
N.CHANNEL = N.CHANNELS[1]
local INVALID = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.InvalidChannel or 7
local function rawId(name)
  if not GetChannelName then return nil end
  local id = GetChannelName(name)
  if type(id) == "number" and id > 0 then return id end
  return nil
end
-- whether the game lists a channel as switched off
local function disabled(name)
  if not GetChannelList then return false end
  local list = { GetChannelList() }
  name = name:lower()
  for i = 1, #list, 3 do
    if type(list[i + 1]) == "string" and list[i + 1]:lower() == name then return list[i + 2] == true end
  end
  return false
end
N.Disabled = disabled
N.refusedAt = nil -- when a message to your channel was last refused (InvalidChannel)
local function channelId()
  local id = rawId(N.CHANNEL)
  if not id or disabled(N.CHANNEL) then return nil end
  if N.refusedAt and C.Now() - N.refusedAt < 120 then return nil end
  return id
end
N.ChannelId = channelId
local function channelCount()
  if not GetChannelList then return 0 end
  return math.floor(select("#", GetChannelList()) / 3)
end
-- keep Kina's channels out of every chat window (they never carry chat anyway)
local function hideFromChat()
  if not (ChatFrame_RemoveChannel and NUM_CHAT_WINDOWS) then return end
  for i = 1, NUM_CHAT_WINDOWS do
    local cf = rawget(_G, "ChatFrame" .. i)
    if cf then
      for _, nm in ipairs(N.CHANNELS) do if rawId(nm) then pcall(ChatFrame_RemoveChannel, cf, nm) end end
      if rawId(N.RELAY) then pcall(ChatFrame_RemoveChannel, cf, N.RELAY) end
    end
  end
end
N.HideFromChat = hideFromChat
local function joinName(name)
  local join = JoinTemporaryChannel or JoinChannelByName
  if join then pcall(join, name) end
end
local function leaveName(name)
  if rawId(name) and LeaveChannelByName then N.leaving = true; pcall(LeaveChannelByName, name); N.leaving = nil end
end
local function note(msg) if C.NetNote then pcall(C.NetNote, msg) end end
-- which of Kina's channels a channel name is (1 to 5, "relay", or nil)
function N.Which(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("^%d+%.%s*", ""):lower()
  if name == N.RELAY:lower() then return "relay" end
  for i, nm in ipairs(N.CHANNELS) do if nm:lower() == name then return i end end
  return nil
end

-- the channel you're on can't have you: on to the next one
function N.NextChannel(why)
  leaveName(N.CHANNEL)
  N.refusedAt = nil
  if N.current >= #N.CHANNELS then
    N.gaveUp = true
    note("couldn't join any Kina channel (" .. tostring(why) .. "); trying again in 10 minutes")
    return
  end
  N.current = N.current + 1
  N.CHANNEL = N.CHANNELS[N.current]
  N.joinedNoted, N.joinTries = false, 0
  note(N.CHANNELS[N.current - 1] .. " " .. tostring(why) .. "; moving to " .. N.CHANNEL)
  N.Join()
end

N.joinTries = 0
function N.Join()
  if not N.Enabled() then return end
  if channelId() then N.joinTries = 0; hideFromChat(); return true end
  if N.gaveUp then return end
  N.joinTries = N.joinTries + 1
  -- still switched off after asking again: too busy to have you
  -- 2.0.4 (Taylor ended up on KinaNetworkB with nobody turning him away): a slow join at
  -- login is not a busy channel. Kina moves on only when the game says so: the channel is
  -- listed but switched off after several tries, or a notice says it's full or locked
  -- (handled with the channel notices below). Otherwise it keeps asking for the same one.
  if rawId(N.CHANNEL) and disabled(N.CHANNEL) and N.joinTries > 4 then return N.NextChannel("is too busy to let you in") end
  joinName(N.CHANNEL)
  if C.After then C.After(2, function()
    hideFromChat()
    local id = channelId()
    if id and not N.joinedNoted then
      N.joinedNoted = true
      note("joined the Kina network (" .. N.CHANNEL .. ", channel " .. id .. ")")
      if N.Presence then N.Presence() end
    elseif not id and N.joinTries == 3 and channelCount() >= 18 then
      note("can't join the Kina network: you're in nearly every chat channel the game allows (20)")
    end
  end) end
end
function N.Joined() return channelId() ~= nil end

-- the game's notices about Kina's channels
local LOCKED = { WRONG_PASSWORD = true, BANNED = true, NOT_ALLOWED_IN_CHANNEL = true }
local noticeFrame = CreateFrame("Frame")
noticeFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
noticeFrame:SetScript("OnEvent", function(_, _, notice, _, _, fullName, _, _, _, _, chanName)
  local which = N.Which(chanName) or N.Which(fullName)
  if not which then return end
  if which == "relay" then
    if LOCKED[notice] and N.Relay then N.Relay.Blocked() end
    return
  end
  if which == N.trying then
    if notice == "YOU_JOINED" or notice == "YOU_CHANGED" then N.LetIn(which)
    elseif LOCKED[notice] then leaveName(N.CHANNELS[which]); N.trying = nil; N.TryEarlier(which + 1) end
    return
  end
  if which ~= N.current then return end
  if LOCKED[notice] then N.NextChannel(notice == "NOT_ALLOWED_IN_CHANNEL" and "is too busy to let you in" or "is locked")
  elseif notice == "YOU_LEFT" and not N.leaving then if C.After then C.After(2, N.Join) end end
end)

-- every 10 minutes from a later channel: try the earlier ones, first to last; the first
-- that lets you in becomes yours and the one you were on is left
function N.TryEarlier(i)
  i = i or 1
  if i >= N.current or not N.Enabled() then N.trying = nil; return end
  N.trying = i
  joinName(N.CHANNELS[i])
  if C.After then C.After(4, function()
    if N.trying ~= i then return end
    if rawId(N.CHANNELS[i]) and not disabled(N.CHANNELS[i]) then N.LetIn(i)
    else leaveName(N.CHANNELS[i]); N.trying = nil; N.TryEarlier(i + 1) end
  end) end
end
function N.LetIn(i)
  N.trying = nil
  if i >= N.current then return end
  local was = N.CHANNEL
  N.current, N.CHANNEL, N.refusedAt = i, N.CHANNELS[i], nil
  leaveName(was)
  hideFromChat()
  note("back on " .. N.CHANNEL .. " (left " .. was .. ")")
  if N.Relay then N.Relay.Reset() end
  if N.Presence then N.Presence() end
end
function N.Retry()
  if not N.Enabled() then return end
  if N.gaveUp then N.gaveUp = false; N.current, N.CHANNEL, N.joinTries = 1, N.CHANNELS[1], 0; return N.Join() end
  if N.current > 1 and not N.trying then N.TryEarlier(1) end
end

------------------------------------------------------------------ sending (paced)
-- The game allows each addon about one message a second (a burst of a few, then one a
-- second); more are dropped. Kina keeps under it: a bucket of 6 that refills one a
-- second, and a message the game turns away goes back to the front of the line.
local queue = {}
local tokens, acc = 6, 0
local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local sender = CreateFrame("Frame")
sender:Hide()
local function sendOne(item)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return true end
  local ok, res
  if item.kind == "CHANNEL" then
    local id = channelId()
    if not id then
      -- 1.0.9: not joined (yet): keep it for up to 10 minutes instead of dropping it
      item.t0 = item.t0 or C.Now()
      if C.Now() - item.t0 > 600 then return true end
      N.Join()
      return "wait"
    end
    ok, res = pcall(C_ChatInfo.SendAddonMessage, N.PREFIX, item.msg, "CHANNEL", tostring(id))
    if ok and res == INVALID then
      -- refused: the channel is switched off for you; ask to join again, and keep the note
      N.refusedAt = C.Now()
      item.t0 = item.t0 or C.Now()
      N.Join()
      return "wait"
    end
    if ok and N.Relay and N.Relay.IsRelay() then N.Relay.Lift(N.MeFull(), item.msg) end
  elseif item.kind == "RELAY" then
    local rid = rawId(N.RELAY)
    if not rid or disabled(N.RELAY) then return true end
    ok, res = pcall(C_ChatInfo.SendAddonMessage, N.PREFIX, item.msg, "CHANNEL", tostring(rid))
    if ok and C.NetLog then pcall(C.NetLog, "out", "RELAY", nil, item.msg, true) end
    if ok and THROTTLED and res == THROTTLED then return false end
    return true
  else
    ok, res = pcall(C_ChatInfo.SendAddonMessage, N.PREFIX, item.msg, "WHISPER", N.WhisperName(item.to))
  end
  if ok and THROTTLED and res == THROTTLED then return false end
  if ok and item.kind == "CHANNEL" then sentRecently[item.msg] = C.Now() end
  if ok and C.NetLog then pcall(C.NetLog, "out", item.kind == "CHANNEL" and "CHANNEL" or "WHISPER", item.to, item.msg, true) end
  return true
end
-- forget old ones now and then
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function()
  local now = C.Now()
  for m, t in pairs(sentRecently) do if now - t > 60 then sentRecently[m] = nil end end
end) end
sender:SetScript("OnUpdate", function(self, el)
  acc = acc + el
  if acc >= 1 then acc = acc - 1; tokens = math.min(6, tokens + 1) end
  if #queue == 0 then self:Hide(); return end
  -- big transfers wait out fights in dungeons and raids
  if InCombatLockdown and InCombatLockdown() and IsInInstance and IsInInstance() then return end
  while tokens >= 1 and queue[1] do
    local item = table.remove(queue, 1)
    tokens = tokens - 1
    local r = sendOne(item)
    if r == "wait" then table.insert(queue, 1, item); tokens = 0; break end
    if not r then table.insert(queue, 1, item); tokens = 0; break end
  end
end)
N.Queued = function() return #queue end
local function push(item)
  if #queue > 3000 then return end
  -- small notes go before big transfers
  if item.urgent then
    local pos = 1
    while queue[pos] and queue[pos].urgent do pos = pos + 1 end
    table.insert(queue, pos, item)
  else queue[#queue + 1] = item end
  sender:Show()
end
function N.Broadcast(msg) if N.Enabled() then push({ kind = "CHANNEL", msg = msg, urgent = true }) end end
-- big transfers (a price scan): behind the small notes
function N.BroadcastBulk(msg) if N.Enabled() and #msg <= 255 then push({ kind = "CHANNEL", msg = msg }) end end
-- to one character: only someone heard from in the last few minutes (never "No player named")
local heard = {}
N.heard = heard
-- 1.0.9 (the scans never arrived): Forever shows "First Surname", but a message to one
-- character goes to the character's name alone (plus its realm if it has one)
N.whisperAs = {}
function N.WhisperName(to)
  if type(to) ~= "string" then return to end
  local known = N.whisperAs[short(to):lower()]
  if known then return known end
  local name, realm = to:match("^([^%-]+)%-?(.*)$")
  name = (name or to):match("^(%S+)") or name
  return (realm and realm ~= "") and (name .. "-" .. realm) or name
end
function N.Heard(name) local t = heard[short(name):lower()]; return t and (C.Now() - t) < 5 * 60 end
function N.Tell(to, msg, bulk)
  if not (N.Enabled() and to and N.Heard(to)) then return false end
  if #msg > 255 then return false end
  push({ kind = "WHISPER", to = to, msg = msg, urgent = not bulk })
  return true
end

------------------------------------------------------------------ receiving
local handlers = {}
-- N.On("F", function(from, fields, raw, how) ... end)
function N.On(kind, fn) handlers[kind] = handlers[kind] or {}; table.insert(handlers[kind], fn) end
local function split(msg)
  local out = {}
  for f in (msg .. "|"):gmatch("([^|]*)|") do out[#out + 1] = f end
  return out
end
N.Split = split
local function dispatch(from, msg, how)
  heard[from:lower()] = C.Now()
  local kind = msg:match("^([^|]+)")
  for _, fn in ipairs(handlers[kind or ""] or {}) do
    local ok, err = pcall(fn, from, split(msg), msg, how)
    if not ok and C.LogError then C.LogError("net " .. tostring(kind), err) end
  end
end
N.Dispatch = dispatch
-- relayed notes heard lately, so one heard twice (two relays) counts once
local relayed = {}
function N.SeenRelayed(origin, inner)
  local k = origin:lower() .. "\1" .. inner
  local now = C.Now()
  if relayed[k] and now - relayed[k] < 120 then return true end
  relayed[k] = now
  return false
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(120, function()
  local now = C.Now()
  for k, t in pairs(relayed) do if now - t > 120 then relayed[k] = nil end end
end) end
C.On("CHAT_MSG_ADDON", function(_, prefix, msg, how, sender, _target, _zone, _localId, chanName)
  if prefix ~= N.PREFIX or type(msg) ~= "string" or type(sender) ~= "string" then return end
  if how == "CHANNEL" and not N.Enabled() then return end
  local from = short(sender)
  local which = how == "CHANNEL" and N.Which(chanName) or nil
  if which == "relay" then
    if not isMe(from, msg) and N.Relay then N.Relay.OnHub(from, msg) end
    return
  end
  if how == "CHANNEL" and which == N.current then N.refusedAt = nil; N.lastHeard = C.Now() end
  if isMe(from, msg) then return end
  if how == "CHANNEL" and which and which ~= N.current then return end -- a channel being tried
  -- a note passed on from another channel: W|origin|the note
  local origin, inner = msg:match("^W|([^|]+)|(.+)$")
  if origin then
    if isMe(origin, inner) or N.SeenRelayed(origin, inner) then return end
    if C.NetLog then pcall(C.NetLog, "in", "RELAYED", origin, inner, true, from) end
    return dispatch(origin, inner, how)
  end
  do -- how to reach them directly: their character name (and realm, if the game gave one)
    local nm, realm = tostring(sender):match("^([^%-]+)%-?(.*)$")
    nm = nm and nm:match("^(%S+)") or nm
    if nm then N.whisperAs[from:lower()] = (realm and realm ~= "") and (nm .. "-" .. realm) or nm end
  end
  if C.NetLog then pcall(C.NetLog, "in", how == "CHANNEL" and N.CHANNEL or how, from, msg, true) end
  if how == "CHANNEL" and N.Relay and N.Relay.IsRelay() then N.Relay.Lift(from, msg) end
  dispatch(from, msg, how)
end)

------------------------------------------------------------------ relays
-- One Kina on each channel (the relay) also sits in KinaRelay. It lifts the notes it hears
-- on its own channel onto the relay channel, wrapped with who said them (W|origin|note),
-- and drops the notes other channels' relays lift into its own channel. Only the network's
-- notes travel (presence, versions, price offers, asks and scans); never the relay's own
-- housekeeping. Who's the relay:
--  * the relay says so on its channel once a minute: RN|<channel>|<when it started>
--  * a Kina that has been on its channel 2 minutes and heard no relay there for 3 claims,
--    after a wait set by its name (so two don't claim at once)
--  * two relays on one channel: the one that started later stands down
--  * never in an instance, with the network off, or with too few chat channels left
local R = {}
N.Relay = R
R.on = false
R.started = nil
R.lastRN = 0          -- when a relay was last heard on your channel
R.blockedUntil = 0
R.hubRelays = {}      -- [name] = { ch, t }: relays heard on the relay channel
R.TRAVEL = { P = true, V = true, O = true, PS = true, PQ = true, PZB = true, PZ = true, PZE = true }
function R.IsRelay() return R.on and rawId(N.RELAY) ~= nil and not disabled(N.RELAY) end
local function relayPush(msg) push({ kind = "RELAY", msg = msg, urgent = not msg:find("^W|[^|]+|PZ") }) end
-- other channels' relays heard on the relay channel lately (no point lifting notes if none)
function R.Others()
  local n, now = 0, C.Now()
  for _, r in pairs(R.hubRelays) do if now - r.t < 180 and r.ch ~= N.current then n = n + 1 end end
  return n
end
function R.Lift(origin, msg)
  local kind = msg:match("^([^|]+)")
  if not R.TRAVEL[kind or ""] then return end
  if R.Others() == 0 then return end
  local w = "W|" .. origin .. "|" .. msg
  if #w > 255 then return end
  relayPush(w)
end
function R.OnHub(from, msg)
  local ch, st = msg:match("^RN|(%d+)|(%w+)")
  if ch then R.hubRelays[from:lower()] = { name = from, ch = tonumber(ch), t = C.Now() }; return end
  if not R.IsRelay() then return end
  local origin, inner = msg:match("^W|([^|]+)|(.+)$")
  if not origin or isMe(origin, inner) or N.SeenRelayed(origin, inner) then return end
  if C.NetLog then pcall(C.NetLog, "in", "RELAYED", origin, inner, true, from) end
  if channelId() then push({ kind = "CHANNEL", msg = msg, urgent = not inner:find("^PZ") }) end
  dispatch(origin, inner, "CHANNEL")
end
local function standDown(why)
  if not R.on then return end
  R.on, R.started = false, nil
  leaveName(N.RELAY)
  note("stopped relaying (" .. why .. ")")
end
function R.Blocked() R.blockedUntil = C.Now() + 30 * 60; standDown("the relay channel turned you away") end
function R.Reset() standDown("changed channel"); R.lastRN = C.Now() end
local function mayRelay()
  if not (N.Enabled() and channelId()) then return false end
  if C.Now() < R.blockedUntil then return false end
  if IsInInstance and IsInInstance() then return false end
  if not R.on and channelCount() > 15 then return false end
  return true
end
N.On("RN", function(from, f)
  local st = tonumber(f[3] or "", 16) or 0
  if tonumber(f[2]) ~= N.current then return end
  R.lastRN = C.Now()
  -- two relays: the later one stands down (ties: by name)
  if R.on and (st < (R.started or 0) or (st == R.started and from:lower() < N.MeFull():lower())) then
    standDown("another Kina relays this channel")
  end
end)
N.joinedAt = nil
function R.Tick()
  local now = C.Now()
  if not mayRelay() then standDown("not available"); N.joinedAt = nil; return end
  N.joinedAt = N.joinedAt or now
  if R.on then
    if not rawId(N.RELAY) then joinName(N.RELAY) end
    -- 2.0: a check-in every 2.5 minutes (others claim only after 3 minutes without one)
    if now - (R.lastSent or 0) < 150 then return end
    R.lastSent = now
    local msg = "RN|" .. N.current .. "|" .. string.format("%x", math.floor(R.started or now))
    N.Broadcast(msg)
    relayPush(msg)
    return
  end
  if now - N.joinedAt < 120 or now - R.lastRN < 180 then return end
  -- claim after a wait set by your name (0 to 40 seconds)
  local h = 0
  for i = 1, #N.MeFull() do h = (h * 31 + N.MeFull():byte(i)) % 41 end
  if C.After then C.After(h, function()
    if R.on or C.Now() - R.lastRN < 180 or not mayRelay() then return end
    R.on, R.started = true, C.Now()
    joinName(N.RELAY)
    if C.After then C.After(3, hideFromChat) end
    note("relaying this channel (" .. N.CHANNEL .. ") to the other Kina channels")
    R.Tick()
  end) end
end
C.On("PLAYER_ENTERING_WORLD", function() if IsInInstance and IsInInstance() then standDown("in an instance") end end)

------------------------------------------------------------------ the developer online
N.devSeen = nil      -- when the developer was last heard online
N.devName = nil      -- which of their characters
N.devShown = false   -- the chat line: once a session, never repeated (Taylor)
N.devLook = nil      -- their earned cosmetics: { standing, level, recruits, bond, class }
function N.DevOnline()
  if N.IAmDeveloper() then return true, N.Me() end
  return N.devSeen ~= nil and (C.Now() - N.devSeen) < N.ONLINE_HOLD, N.devName
end
N.On("O", function(from, f)
  if not N.IsDeveloper(from) then return end -- only the developer may say this
  N.devSeen, N.devName = C.Now(), from
  -- O|version|standing|level|recruits|bond|class
  N.devLook = { ver = f[2], standing = f[3] ~= "" and f[3] or "Unproven", level = tonumber(f[4]) or 1, recruits = tonumber(f[5]) or 0,
    bond = tonumber(f[6]), class = f[7] ~= "" and f[7] or nil }
  if not N.devShown then
    N.devShown = true
    C.Print("|cffffc54aKina (from the developer):|r I'm online now. Send me your bugs, ideas and requests: Help > Feedback, or /kina feedback.", true)
  end
  if C.Feedback and C.Feedback.OnDevOnline then C.Feedback.OnDevOnline(from) end
  if C.Refresh then C.Refresh() end
end)
-- what the developer's badge shows: their own earned cosmetics
function N.MyLook()
  local m = C.Rep and C.Rep.Mine and C.Rep.Mine() or {}
  local partner = C.Pair and C.Pair.PartnerName and C.Pair.PartnerName()
  local bond = partner and C.Cos and C.Cos.BondFor and C.Cos.BondFor(partner)
  local _, cls = UnitClass and UnitClass("player")
  return { standing = m.standing or "Unproven", level = m.level or 1, recruits = C.Mentor and C.Mentor.Count and C.Mentor.Count() or 0,
    bond = bond, class = cls, founder = true }
end
-- (silent: the heartbeat keeps players' "online" right; the chat line shows once)
local function announce()
  if not (N.IAmDeveloper() and N.Enabled()) then return end
  local l = N.MyLook()
  N.Broadcast(string.format("O|%s|%s|%d|%d|%s|%s", tostring(C.version), l.standing, l.level, l.recruits,
    l.bond and tostring(math.floor(l.bond)) or "", l.class or ""))
end
N.Announce = announce

------------------------------------------------------------------ presence
-- 1.0.9: every Kina on the network says it's here every 5 minutes (P|version), so Kinas
-- know who's online and newer scans get offered to people who logged in after them
N.PRESENCE_EVERY = 5 * 60
function N.Presence()
  if not (N.Enabled() and channelId()) then return end
  N.Broadcast("P|" .. tostring(C.version))
  if C.NetPrices and C.NetPrices.Announce then pcall(C.NetPrices.Announce) end
end
N.On("P", function() end) -- (heard: counted by the log)
local function keepJoined()
  if N.Enabled() and not channelId() then N.Join() end
end

------------------------------------------------------------------ start
C.On("PLAYER_LOGIN", function()
  if not C.After then return end
  C.After(6, function() N.Join() end)
  C.After(12, announce)
  C.After(20, function() N.Presence() end)
end)
C.On("PLAYER_ENTERING_WORLD", function() if C.After then C.After(8, keepJoined) end end)
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(30, function() pcall(keepJoined) end)
  C_Timer.NewTicker(60, function() pcall(R.Tick) end)
  C_Timer.NewTicker(600, function() pcall(N.Retry) end)
  C_Timer.NewTicker(N.PRESENCE_EVERY, function() pcall(N.Presence) end)
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(N.ANNOUNCE_EVERY, function() pcall(announce) end) end
C.On("CHANNEL_UI_UPDATE", function() if channelId() then hideFromChat() end end)

------------------------------------------------------------------ the developer's badge
-- Up top beside the Kina nameplate: the developer's portrait with their earned cosmetics
-- (standing ring, Kina level, mentor stars, bond crest) and a green blip while they're
-- online. Click: Help > Feedback. Hidden while they're offline.
local badge
local function buildBadge()
  local u = C.ui
  if not (u and u.frame and u.nameplate) then return nil end
  local b = CreateFrame("Button", nil, u.frame)
  b:SetSize(52, 52); b:SetPoint("RIGHT", u.nameplate, "LEFT", -6, 4)
  b:SetFrameLevel((u.frame:GetFrameLevel() or 1) + 50)
  b.box = CreateFrame("Frame", nil, b); b.box:SetAllPoints()
  b.portrait = b.box:CreateTexture(nil, "ARTWORK")
  if C.Cos and C.Cos.Portrait then
    local ok, o = pcall(C.Cos.Portrait, b.box, b.portrait, {})
    if ok then b.cos = o end
  end
  b.blip = b:CreateTexture(nil, "OVERLAY", nil, 7); b.blip:SetSize(12, 12); b.blip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  b.blip:SetTexture("Interface\\COMMON\\Indicator-Green")
  b.ring = b:CreateTexture(nil, "OVERLAY", nil, 6); b.ring:SetSize(16, 16); b.ring:SetPoint("CENTER", b.blip, "CENTER")
  b.ring:SetColorTexture(0, 0, 0, 0)
  b.label = b:CreateFontString(nil, "OVERLAY"); b.label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE"); b.label:SetPoint("TOP", b, "BOTTOM", 0, 2)
  b.label:SetText("|cff3fd03fdev online|r")
  b:SetScript("OnClick", function()
    if C.Feedback and C.Feedback.OpenPopup then C.Feedback.OpenPopup() end
  end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    local _, name = N.DevOnline()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("|cff3fd03fKina developer online|r")
    GameTooltip:AddLine(name or "", 1, 0.82, 0.3)
    GameTooltip:AddLine("Click to send bugs, ideas and requests (Help > Feedback).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:Hide()
  return b
end
function N.UpdateBadge()
  local on = N.DevOnline()
  if not on or not N.Enabled() then if badge then badge:Hide() end; return end
  badge = badge or buildBadge()
  if not badge then return end
  local look = N.IAmDeveloper() and N.MyLook() or N.devLook or {}
  if badge.cos and C.Cos.UpdatePortrait then
    pcall(C.Cos.UpdatePortrait, badge.cos, look.standing or "Unproven", look.level or 1, look.recruits or 0)
    if C.Cos.SetBond then pcall(C.Cos.SetBond, badge.cos, look.bond) end
    if C.Cos.SetFounder then pcall(C.Cos.SetFounder, badge.cos, true) end -- (Taylor: with the founder's ring)
  end
  -- their class crest (an unmasked texture over the round portrait, as profiles do)
  if look.class and C.Profile and C.Profile.ClassIcon then pcall(C.Profile.ClassIcon, badge.portrait, look.class)
  else badge.portrait:SetTexture("Interface\\AddOns\\Kina\\Media\\KinaLogo") end
  badge:Show()
end
function N.badgeShown() return badge ~= nil and badge:IsShown() end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(3, function() pcall(N.UpdateBadge) end) end
