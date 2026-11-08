local _, C = ...
-- Kina: installs shared (the mentor star), 0.9.10.
-- Someone who shows Kina to a new player gets the credit once that player's Kina is
-- really installed and in use (Taylor: "only shares count when an install is actually
-- done"). The rules:
--   - Only a brand-new Kina can give credit: one with no farms or tour behind it.
--   - The new player names who told them about Kina (asked after the welcome tour, or
--     /kina mentor Name). If they don't, the first person they farm with gets it: the
--     farm's leader, or their first partner when they led it themselves.
--   - It only counts after the new player's first qualifying farm (15+ minutes, the
--     same rule as Kina level).
--   - Never your own characters, and each new player counts once (by Kina and by name).
--   - The new player's Kina sends the credit; the mentor's Kina keeps the count and
--     answers, so the credit lands only when both Kinas have really talked.
-- Messages (Share.lua, prefix KinaShare): N|uid|mentor|name (credit), A|uid|recruitUid (thanks).
local M = {}
C.Mentor = M
local GOLD, GREEN = "|cffffd100", "|cff33ff66"
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
  name = first(name) or first(from)
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

-- the person who told you about Kina
function M.Name(who)
  local d = db()
  local n = first(who)
  if not d.eligible then C.Print("only a new Kina can name who told them about it."); return false end
  if d.done then C.Print("you already gave " .. tostring(d.target) .. " the credit."); return false end
  if not n then C.Print("who told you about Kina? " .. GOLD .. "/kina mentor Name|r"); return false end
  if n == me() or C.IsMyChar(n) then C.Print("that's one of your own characters."); return false end
  d.named = n
  if not d.qualified then
    C.Print(string.format("thanks! %s gets the credit after your first farm of 15 minutes or more.", n))
  end
  d.target = n
  M.Try()
  return true
end

local function lastFarmPartners(s)
  local out = {}
  for _, p in ipairs(s.party or {}) do local n = first(p.name); if n and n ~= me() then out[#out + 1] = n end end
  return out
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
  if not d.named then
    -- nobody named: the leader of this farm, or my first partner if I led it
    local leader = first(s.sync and s.sync.leader)
    local mates2 = lastFarmPartners(s)
    local t = (leader and leader ~= me()) and leader or mates2[1]
    if t and not C.IsMyChar(t) then d.target = t end
  end
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
    local prev = C.Share.onHello
    C.Share.onHello = function(from, uid, a, channel)
      if prev then prev(from, uid, a, channel) end
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

-- asked once, after the welcome tour (new players only)
if StaticPopupDialogs then
  StaticPopupDialogs.KINA_MENTOR = {
    text = "Who told you about Kina?\n\n|cff9d9d9dTheir character name. They get the credit after your first farm of 15 minutes or more. Leave it empty and the first person you farm with gets it.|r",
    button1 = ACCEPT or "OK", button2 = "Skip",
    hasEditBox = true, maxLetters = 24, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(self)
      local eb = self.editBox or self.EditBox
      local n = eb and eb:GetText() or ""
      if n:match("%S") then M.Name(n) end
    end,
    EditBoxOnEnterPressed = function(self)
      local p = self:GetParent(); local b = p.button1 or (p.GetButton1 and p:GetButton1()); if b then b:Click() end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  }
end
function M.Ask()
  local d = db()
  if not M.Eligible() or d.named or d.asked then return end
  d.asked = C.Now()
  if C.ShowPopup then C.ShowPopup("KINA_MENTOR") end
end
