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
function N.IAmDeveloper() return N.IsDeveloper(N.Me()) end
function N.Enabled() return not (C.settings and C.settings.netOff) end

------------------------------------------------------------------ the channel
local function channelId()
  if not GetChannelName then return nil end
  local id = GetChannelName(N.CHANNEL)
  if type(id) == "number" and id > 0 then return id end
  return nil
end
N.ChannelId = channelId
-- keep the channel out of every chat window (it never carries chat anyway)
local function hideFromChat()
  if not (ChatFrame_RemoveChannel and NUM_CHAT_WINDOWS) then return end
  for i = 1, NUM_CHAT_WINDOWS do
    local cf = rawget(_G, "ChatFrame" .. i)
    if cf then pcall(ChatFrame_RemoveChannel, cf, N.CHANNEL) end
  end
end
-- 1.0.9 (Taylor: "I don't think it's working"): joining at login can fail silently (chat
-- not ready yet, or too many channels); Kina now keeps trying every 30 seconds and says so
-- in the network log
N.joinTries = 0
function N.Join()
  if not N.Enabled() then return end
  if channelId() then hideFromChat(); return true end
  local join = JoinTemporaryChannel or JoinChannelByName
  N.joinTries = N.joinTries + 1
  if join then pcall(join, N.CHANNEL) end
  if C.After then C.After(2, function()
    hideFromChat()
    local id = channelId()
    if id and not N.joinedNoted then
      N.joinedNoted = true
      if C.NetNote then pcall(C.NetNote, "joined the Kina network (channel " .. id .. ")") end
      if N.Presence then N.Presence() end
    elseif not id and N.joinTries == 3 and C.NetNote then
      pcall(C.NetNote, "can't join the Kina network yet (you may be in the most chat channels the game allows); still trying")
    end
  end) end
end
function N.Joined() return channelId() ~= nil end

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
  else
    ok, res = pcall(C_ChatInfo.SendAddonMessage, N.PREFIX, item.msg, "WHISPER", N.WhisperName(item.to))
  end
  if ok and THROTTLED and res == THROTTLED then return false end
  if ok and C.NetLog then pcall(C.NetLog, "out", item.kind == "CHANNEL" and "CHANNEL" or "WHISPER", item.to, item.msg, true) end
  return true
end
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
C.On("CHAT_MSG_ADDON", function(_, prefix, msg, how, sender)
  if prefix ~= N.PREFIX or type(msg) ~= "string" then return end
  if how == "CHANNEL" and not N.Enabled() then return end
  local from = short(sender)
  if from:lower() == N.Me():lower() then return end
  heard[from:lower()] = C.Now()
  do -- how to reach them directly: their character name (and realm, if the game gave one)
    local nm, realm = tostring(sender):match("^([^%-]+)%-?(.*)$")
    nm = nm and nm:match("^(%S+)") or nm
    if nm then N.whisperAs[from:lower()] = (realm and realm ~= "") and (nm .. "-" .. realm) or nm end
  end
  if C.NetLog then pcall(C.NetLog, "in", how, from, msg, true) end
  local kind = msg:match("^([^|]+)")
  for _, fn in ipairs(handlers[kind or ""] or {}) do
    local ok, err = pcall(fn, from, split(msg), msg, how)
    if not ok and C.LogError then C.LogError("net " .. tostring(kind), err) end
  end
end)

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
