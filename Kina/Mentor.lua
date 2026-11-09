local _, C = ...
-- Kina: installs shared (the mentor star). 0.9.10; reworked 0.9.17 (Taylor: "asking
-- someone to type in someone's convoluted name isn't the play").
-- How it works now:
--   - A Kina user shares Kina in party chat (/kina share, or "Share Kina" on the You
--     page): Kina posts the download link to party chat and remembers who was there.
--   - When a brand-new Kina makes first contact with other Kinas in a party, every Kina
--     in that party that shared the link with that player (and is still in the party)
--     says when it shared. The new player's Kina picks whoever shared FIRST.
--   - That first sharer's account gets the install once the new player has done a farm
--     of 15 minutes or more (the same rule as Kina level), and both Kinas have talked.
--   - Only a brand-new Kina can give credit; never your own characters; each new player
--     counts once (by Kina and by name). No sharer in the party at first contact: nobody.
-- Messages (Share.lua): J|uid|sharedAt|recruit (I shared with you), N|uid|mentor|name
-- (the credit), A|uid|recruitUid (thanks). A new Kina's hello carries flag "n".
local M = {}
C.Mentor = M
local GOLD, GREEN = "|cffffc54a", "|cff33ff66"
local RETRY = 600

local function db()
  C.db.mentor = C.db.mentor or {}
  return C.db.mentor
end
local function first(n)
  if type(n) ~= "string" or (issecretvalue and issecretvalue(n)) then return nil end
  local f = n:match("^%s*([^%s%-]+)")
  if not f then return nil end
  return f:sub(1, 1):upper() .. f:sub(2):lower()
end
M.First = first
local function me() return first(UnitName and UnitName("player")) end

------------------------------------------------------------------ the mentor's side
function M.Count()
  local n = 0
  for _ in pairs(db().recruits or {}) do n = n + 1 end
  return n
end
function M.Recruits()
  local out = {}
  for uid, r in pairs(db().recruits or {}) do out[#out + 1] = { uid = uid, name = r.name, t = r.t } end
  table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
  return out
end

local function onCredit(from, rest, channel)
  local uid, target, name = rest:match("^(%x+)|([^|]*)|([^|]*)$")
  if not uid or uid == (C.Share and C.Share.UID()) then return end
  if first(target) ~= me() then return end -- someone else's credit (sent to the whole group)
  -- 0.9.13 (exploit test): the recruit is whoever SENT the credit, never a name inside it
  -- (one other account could otherwise send 50 made-up recruits)
  name = first(from)
  if not name or C.IsMyChar(from) or C.IsMyChar(name) then return end -- never your own characters
  local d = db()
  d.recruits = d.recruits or {}
  local known = d.recruits[uid]
  if not known then
    for _, r in pairs(d.recruits) do if r.name == name then known = r end end
  end
  if not known then
    d.recruits[uid] = { name = name, t = C.Now() }
    C.Print(string.format("%s%s installed Kina because of you: that's %d install%s shared.|r", GOLD, name, M.Count(), M.Count() == 1 and "" or "s"))
    if C.Share and C.Share.Announce then pcall(C.Share.Announce, true) end
    if C.Refresh then pcall(C.Refresh) end
  end
  -- thank them either way, so their Kina stops asking
  local ch = C.Share.GroupChannel()
  if ch and C.Share.InMyGroup(from) then C.Share.Send(table.concat({ "A", C.Share.UID(), uid }, "|"), ch)
  else C.Share.Send(table.concat({ "A", C.Share.UID(), uid }, "|"), "WHISPER", from) end
end

------------------------------------------------------------------ the new player's side
function M.Eligible()
  local d = db()
  return d.eligible == true and not d.done
end

------------------------------------------------------------------ sharing the link
local SHARE_TEXT = "Kina: a free farming partner add-on for WoW Forever. Shared loot log, fair splits, one-click debts. Get it: %s"
local lastShare = 0
function M.Share()
  local inRaid = IsInRaid and IsInRaid()
  local inParty = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0)
  if not inParty then C.Print("join a party first: Kina shares its link in party chat."); return false end
  local now = GetTime and GetTime() or 0
  if now - lastShare < 60 then C.Print("you just shared Kina: give it a minute."); return false end
  lastShare = now
  if SendChatMessage then pcall(SendChatMessage, string.format(SHARE_TEXT, C.UPDATE_URL or "github.com/Avicularia/Kina/releases"), inRaid and "RAID" or "PARTY") end
  -- remember who was there (first share to each player wins; kept 30 days)
  local d = db(); d.shared = d.shared or {}
  local n = 0
  local names = {}
  local raid = IsInRaid and IsInRaid()
  for i = 1, raid and 40 or 4 do
    local u = (raid and "raid" or "party") .. i
    if UnitExists and UnitExists(u) then names[#names + 1] = UnitName(u) end
  end
  for _, name in ipairs(names) do
    local f = first(name)
    if f and f ~= me() and not C.IsMyChar(f) then
      if not d.shared[f] then d.shared[f] = C.Now() end
      n = n + 1
    end
  end
  for f, t in pairs(d.shared) do if C.Now() - t > 30 * 86400 then d.shared[f] = nil end end
  C.Print(string.format("shared Kina's link in %s chat. If someone installs it and their Kina first meets yours in a party, the install is yours.", inRaid and "raid" or "party"))
  return true
end

-- a brand-new Kina said hello in my group: if I shared the link with them, say when
local claimed = {}
local function onNewKina(from)
  local d = db()
  local f = first(from)
  local t = f and d.shared and d.shared[f]
  if not t or claimed[f] then return end
  local ch = C.Share.GroupChannel()
  if ch and C.Share.InMyGroup(from) then
    claimed[f] = true
    C.Share.Send(table.concat({ "J", C.Share.UID(), tostring(t), f }, "|"), ch)
  end
end

------------------------------------------------------------------ first contact
-- the new player's side: collect the "I shared with you" claims for a little while after
-- first contact, then the earliest sharer still in the party gets it
local window, claims
local function decide()
  local d = db()
  if d.decided then return end
  d.decided = C.Now()
  local best, bt
  for who, t in pairs(claims or {}) do
    if C.InGroupName and C.InGroupName(who) and not C.IsMyChar(who) and (not bt or t < bt) then best, bt = who, t end
  end
  if best then
    d.target = best
    C.Print(string.format("%s shared Kina with you: they get the credit after your first farm of 15 minutes or more.", best))
  end
  claims = nil
  M.Try()
end
local function onClaim(from, rest)
  local uid, t, recruit = rest:match("^(%x+)|(%d+)|([^|]+)$")
  local d = db()
  if not uid or d.decided or not d.eligible or first(recruit) ~= me() then return end
  t = tonumber(t)
  if not t or t > C.Now() + 60 then return end
  claims = claims or {}
  local f = first(from)
  if f and (not claims[f] or t < claims[f]) then claims[f] = t end
end
local function firstContact()
  local d = db()
  if not d.eligible or d.decided or window then return end
  window = true
  claims = claims or {}
  if C.After then C.After(20, function() window = nil; pcall(decide) end) else decide() end
end

-- a farm ended: was it the first one that counts?
function M.OnFarmEnd(s, f)
  local d = db()
  if not d.eligible or d.done or d.qualified then return end
  local R = C.Rep
  local secs, mates = tonumber(f[7]) or 0, tonumber(f[10]) or 0
  if mates < 1 or secs < ((R and R.FARM_MIN_SECS) or 900) then return end
  if R and R.Unqualified and R.Unqualified(f) then return end
  d.qualified = C.Now()
  M.Try()
end

local lastTry = {}
function M.Try(heardFrom)
  local d = db()
  if not d.eligible or d.done or not d.qualified or not d.target then return false end
  local S = C.Share
  if not (S and S.Send and S.UID) then return false end
  local now = GetTime and GetTime() or 0
  if lastTry[d.target] and now - lastTry[d.target] < 20 then return false end
  local msg = table.concat({ "N", S.UID(), d.target, me() or "?" }, "|")
  local ch = S.GroupChannel()
  local sent = false
  if ch and C.InGroupName and C.InGroupName(d.target) then sent = S.Send(msg, ch) end
  if not sent and heardFrom and first(heardFrom) == d.target then sent = S.Send(msg, "WHISPER", heardFrom) end
  if sent then lastTry[d.target] = now end
  return sent
end

local function onThanks(from, rest)
  local uid, recruit = rest:match("^(%x+)|(%x+)$")
  local d = db()
  if not uid or recruit ~= C.Share.UID() or d.done or first(from) ~= d.target then return end
  d.done = C.Now()
  C.Print(string.format("%s%s got the credit for showing you Kina.|r Welcome!", GREEN, d.target))
end

------------------------------------------------------------------ wiring
C.On("INIT", function()
  local d = db()
  if d.eligible == nil then
    -- a brand-new Kina: no farms, no tour, no Kina history on this account
    local fresh = not (C.settings and C.settings.tourSeen)
      and not (C.db.sessions and #C.db.sessions > 0)
      and not (C.Rep and C.Rep.Mine and (C.Rep.Mine().xp or 0) > 0)
    d.eligible = fresh and true or false
    d.born = C.Now()
  end
  if C.Share then
    C.Share.kinds.N = onCredit
    C.Share.kinds.A = onThanks
    C.Share.kinds.J = onClaim
    local prev = C.Share.onHello
    C.Share.onHello = function(from, uid, a, channel)
      if prev then prev(from, uid, a, channel) end
      if C.Share.InMyGroup(from) then
        if a and a.flags and a.flags:find("n", 1, true) then pcall(onNewKina, from) end
        if M.Eligible() and not db().decided then firstContact() end
      end
      if M.Eligible() and db().qualified then M.Try(from) end
    end
  end
end)
-- keep asking now and then until the mentor's Kina answers
if CreateFrame then
  local t, acc = CreateFrame("Frame"), 0
  t:SetScript("OnUpdate", function(_, el)
    acc = acc + el; if acc < RETRY then return end; acc = 0
    if M.Eligible() and db().qualified then pcall(M.Try) end
  end)
end
C.On("GROUP_ROSTER_UPDATE", function() if M.Eligible() and db().qualified then C.After(5, function() pcall(M.Try) end) end end)

-- a new Kina's hello says so (flag "n"), until its first contact has been decided
function M.NewFlag()
  local d = db()
  return (d.eligible == true and not d.decided) and "n" or ""
end
