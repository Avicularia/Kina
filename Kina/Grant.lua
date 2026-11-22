-- Kina 2.0.6: Kina team grants.
-- Taylor: a way to give a player Kina XP / Renown that a bug lost ("our 1:51:48 farm gave us
-- nothing"), usable once, by that player only. Instead of codes that could be passed
-- around, the grant goes straight to the player:
--   /kina grant <name> <amount> <reason>
-- works only on a Kina team character (Deputize, Avic) with the team code entered in
-- Settings. It sends an invisible addon whisper; the player's Kina accepts it only from a
-- team character on the same realm, pays it once (each grant has its own ID, remembered for
-- the whole account), and answers so the sender knows it landed. A player who is offline
-- gets it the next time they're reachable (in your group, online in your guild, or heard on
-- the Kina network): the grant waits in your Kina, checked every minute, for 14 days.
local _, C = ...
local G = {}
C.Grant = G

G.PREFIX = "KinaGrant"
G.TEAM = { deputize = true, avic = true }
G.KEEP = 14 * 86400

local function first(name) return ((tostring(name or "")):match("^([^%-]+)") or ""):match("^(%S+)") or "" end
local function realmOf(name) return (tostring(name or "")):match("%-(.+)$") end
local function norm(r) return (tostring(r or "")):gsub("[%s%-']", ""):lower() end

function G.IsTeam(name) return G.TEAM[first(name):lower()] == true end
function G.CanSend()
  return C.settings and C.settings.adminUnlocked == true and G.IsTeam(UnitName and UnitName("player") or "")
end

local function store()
  local A = _G.KinaDB or C.db
  A.grantsUsed = type(A.grantsUsed) == "table" and A.grantsUsed or {} -- whole account
  return A.grantsUsed
end
local function outbox()
  C.db.grantOut = type(C.db.grantOut) == "table" and C.db.grantOut or {}
  return C.db.grantOut
end

local function newId()
  local t = C.Now and C.Now() or 0
  return string.format("%x%04x", t, math.random(0, 65535))
end

-- 1.0.2 rule: add-on data only ever goes to someone reachable right now (in your group,
-- an online guild member, or whose Kina spoke in the last two minutes), never to someone
-- offline ("No player named ..." in chat)
local function reachable(name)
  return (C.CanWhisper and C.CanWhisper(name)) or (C.GuildOnline and C.GuildOnline(name)) or false
end

local function send(g)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  g.last = C.Now()
  if not reachable(g.to) then return false end
  local reason = (g.reason or ""):gsub("|", "/"):sub(1, 120)
  pcall(C_ChatInfo.SendAddonMessage, G.PREFIX, table.concat({ "G", g.id, tostring(g.xp), reason }, "|"), "WHISPER", g.to)
  g.tries = (g.tries or 0) + 1
  return true
end

function G.Send(to, amount, reason)
  if not G.CanSend() then
    C.Print("|cffff8040Kina team grants only work on a team character with the team code entered in Settings.|r"); return
  end
  amount = math.floor(tonumber(amount) or 0)
  if not to or to == "" or amount <= 0 or amount > 100000 then
    C.Print("usage: /kina grant <name> <amount> <reason>   (amount 1 to 100000)"); return
  end
  local g = { id = newId(), to = to, xp = amount, reason = reason ~= "" and reason or "Kina team grant", t = C.Now() }
  outbox()[g.id] = g
  local sent = send(g)
  C.Print(string.format("|cff4fc3f7Kina grant %s:|r +%d Renown and Kina XP to %s (%s). %s", g.id, amount, to, g.reason,
    sent and "Waiting for their Kina to confirm." or "They're not reachable now (group up, or both online in the guild): it goes when they are, for 14 days."))
end

-- the receiver
function G.Receive(msg, sender)
  local kind, id, a, b = msg:match("^(%a)|([^|]*)|([^|]*)|?(.*)$")
  if kind == "A" then
    local g = outbox()[id or ""]
    if g then
      outbox()[id] = nil
      C.Print(string.format("|cff7CFC00Kina grant %s landed:|r %s got +%d Renown and Kina XP%s.", id, g.to, g.xp, a == "dup" and " (already had it)" or ""))
    end
    return
  end
  if kind ~= "G" or not id or id == "" then return end
  if not G.IsTeam(sender) then return end
  local myRealm = GetRealmName and GetRealmName() or ""
  local r = realmOf(sender)
  if r and myRealm ~= "" and norm(r) ~= norm(myRealm) then return end
  local used = store()
  local reply = "ok"
  if used[id] then reply = "dup"
  else
    local amount = math.floor(tonumber(a) or 0)
    if amount <= 0 or amount > 100000 then return end
    used[id] = { t = C.Now(), xp = amount, from = sender }
    local P = C.Progress
    local st = P and P.State and P.State()
    if not st then return end
    st.renown = (st.renown or 0) + amount
    st.xp = (st.xp or 0) + amount
    local why = (b and b ~= "") and b or "Kina team grant"
    C.Print(string.format("|cffffc54aKina team grant:|r +%d Renown and Kina XP (%s).", amount, why))
    if C.Toast and C.Toast.Notice then pcall(C.Toast.Notice, string.format("+%d Renown and Kina XP", amount), why) end
  end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, G.PREFIX, "A|" .. id .. "|" .. reply, "WHISPER", sender)
  end
end

-- waiting grants: retried every minute and when someone comes online
function G.Retry()
  local now = C.Now()
  for id, g in pairs(outbox()) do
    if now - (g.t or now) > G.KEEP then outbox()[id] = nil
    elseif now - (g.last or 0) >= 55 then send(g) end
  end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, G.PREFIX) end
if CreateFrame then
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("PLAYER_LOGIN")
  f:SetScript("OnEvent", function(_, ev, prefix, msg, _, sender)
    if ev == "CHAT_MSG_ADDON" then
      if prefix == G.PREFIX and type(msg) == "string" then pcall(G.Receive, msg, sender) end
    elseif ev == "PLAYER_LOGIN" then
      local function loop() if C.db then pcall(G.Retry) end; if C.After then C.After(60, loop) end end
      if C.After then C.After(20, loop) end
    end
  end)
end
