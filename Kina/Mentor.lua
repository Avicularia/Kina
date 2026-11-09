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
-- 0.9.23: a party message that works without copying anything (chat links can't be
-- clicked or copied without add-ons): what to search for, then the link
local SHARE_TEXT = "Kina: free farm tracker and loot splitter for WoW Forever. Search \"Kina Farm Groups\" in the CurseForge app: %s"
function M.Link() return C.UPDATE_URL or "curseforge.com/wow/addons/kina-farm-groups-and-gold-splits" end

-- 0.9.23 (Taylor, like RestedXP's video link): a box with the link selected, Ctrl+C to copy
function M.CopyBox(title)
  local link = M.Link()
  if not StaticPopupDialogs then return end
  if not StaticPopupDialogs.KINA_COPY then
    local function eb(self) return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox()) end
    StaticPopupDialogs.KINA_COPY = {
      text = "%s", button1 = OKAY or "Okay", hasEditBox = 1, editBoxWidth = 300,
      timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
      OnShow = function(self, data)
        local e = eb(self); if not e then return end
        e:SetText(M.Link()); e:HighlightText(); if e.SetFocus then e:SetFocus() end
      end,
      EditBoxOnTextChanged = function(e) if e:GetText() ~= M.Link() then e:SetText(M.Link()); e:HighlightText() end end,
      EditBoxOnEnterPressed = function(e) local p = e:GetParent(); if p then p:Hide() end end,
      EditBoxOnEscapePressed = function(e) local p = e:GetParent(); if p then p:Hide() end end,
    }
  end
  C.ShowPopup("KINA_COPY", title or "Press Ctrl+C to copy Kina's link")
end
-- clicking someone without Kina (the party strip): share in party chat, then the copy box
local sharedThisSession = {}
function M.ShareTo(name)
  local f = first(name)
  if f and not sharedThisSession[f] then
    if M.Share() then sharedThisSession[f] = true end
  elseif f then
    C.Print(string.format("you already shared Kina with %s this session: here's the link to copy.", f))
  end
  M.CopyBox("Shared in party chat. Press Ctrl+C to copy the link")
end
local lastShare = 0
function M.Share()
  local inRaid = IsInRaid and IsInRaid()
  local inParty = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0)
  if not inParty then C.Print("join a party first: Kina shares its link in party chat."); return false end
  local now = GetTime and GetTime() or 0
  if now - lastShare < 60 then C.Print("you just shared Kina: give it a minute."); return false end
  lastShare = now
  if SendChatMessage then pcall(SendChatMessage, string.format(SHARE_TEXT, M.Link()), inRaid and "RAID" or "PARTY") end
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
-- 0.9.23 (Taylor, mock approved): the new player picks who showed them Kina, from the
-- Kina users in their party and those they met in the last 7 days. Whoever shared the
-- link in party chat is highlighted (a hint: the new player decides).
local RECENT = 7 * 86400
function M.Candidates()
  local out, seen = {}, {}
  local S = C.Share
  local my = S and S.UID and S.UID()
  for uid, a in pairs(S and S.DB and S.DB().authors or {}) do
    local nm = first((a.char and a.char.from) or a.name)
    if nm and uid ~= my and not seen[nm] and not C.IsMyChar(nm) and a.seen and C.Now() - a.seen < RECENT then
      seen[nm] = true
      out[#out + 1] = { name = nm, uid = uid, seen = a.seen, here = C.InGroupName and C.InGroupName(nm) or false, shared = claims and claims[nm] }
    end
  end
  table.sort(out, function(x, y)
    if (x.shared ~= nil) ~= (y.shared ~= nil) then return x.shared ~= nil end
    if x.shared and y.shared and x.shared ~= y.shared then return x.shared < y.shared end
    if x.here ~= y.here then return x.here end
    return (x.seen or 0) > (y.seen or 0)
  end)
  while #out > 4 do table.remove(out) end
  return out
end
function M.Pick(name)
  local d = db()
  if d.done then return false end
  d.decided = C.Now()
  local f = first(name)
  if f and not C.IsMyChar(f) then
    d.target = f
    C.Print(string.format("|cffffc54a%s showed you Kina:|r they earn a mentor star once you finish your first farm of 15 minutes or more.", f))
    M.Try()
  else
    d.target = nil
    C.Print("got it: you found Kina yourself. Welcome!")
  end
  if M.picker then M.picker:Hide() end
  return true
end
local function decide()
  local d = db()
  if d.decided or d.done then return end
  if #M.Candidates() == 0 then return end
  if M.ShowPicker then pcall(M.ShowPicker) end
end
local function onClaim(from, rest)
  local uid, t, recruit = rest:match("^(%x+)|(%d+)|([^|]+)$")
  local d = db()
  if not uid or d.done or not d.eligible or first(recruit) ~= me() then return end
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
  C.GuardScript(t, "OnUpdate", "Mentor:228", function(_, el)
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

------------------------------------------------------------------ the picker window
function M.ShowPicker()
  local d = db()
  if not d.eligible or d.done then C.Print("this is for brand-new Kina installs."); return end
  local list = M.Candidates()
  if not CreateFrame then return end
  local f = M.picker
  if not f then
    f = CreateFrame("Frame", "KinaWelcomePick", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    M.picker = f
    f:SetSize(440, 340); f:SetPoint("CENTER", 0, 80); f:SetFrameStrata("DIALOG"); f:EnableMouse(true)
    f:SetMovable(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if C.Skin and C.Skin.On and C.Skin.On() and C.Skin.Panel then C.Skin.Panel(f, 8)
    else local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.06, 0.05, 0.95) end
    local np = f:CreateTexture(nil, "ARTWORK"); np:SetSize(210, 60); np:SetPoint("TOP", 0, -10)
    np:SetTexture(C.Cos.Tex("kina_nameplate")); np:SetTexCoord(0, 1, 0, 295 / 512)
    local t1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); t1:SetPoint("TOP", np, "BOTTOM", 0, -4)
    if C.Cos.Font then C.Cos.Font(t1, 18, "OUTLINE") end; t1:SetTextColor(1, 0.77, 0.29); t1:SetText("Welcome to Kina!")
    local t2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t2:SetPoint("TOP", t1, "BOTTOM", 0, -6); t2:SetText("Who showed you Kina?")
    local t3 = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); t3:SetPoint("TOP", t2, "BOTTOM", 0, -6); t3:SetWidth(380)
    t3:SetText("Pick the player who told you about it. Once you finish your first 15-minute farm, they earn a mentor star on their portrait.")
    f.cells = {}
    for i = 1, 4 do
      local c = CreateFrame("Button", nil, f); c:SetSize(100, 110)
      c.box = CreateFrame("Frame", nil, c); c.box:SetSize(56, 56); c.box:SetPoint("TOP", 0, -10)
      c.portrait = c.box:CreateTexture(nil, "ARTWORK")
      c.cos = C.Cos.Portrait(c.box, c.portrait, { model = true }) -- animated rings, live 3D model when in sight
      c.glow = c:CreateTexture(nil, "BACKGROUND"); c.glow:SetSize(130, 130); c.glow:SetPoint("CENTER", c.box, "CENTER")
      c.glow:SetTexture(C.Cos.Tex("fx_round")); c.glow:SetBlendMode("ADD"); c.glow:SetVertexColor(0.3, 1, 0.5); c.glow:SetAlpha(0.45)
      c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); c.name:SetPoint("TOP", c.box, "BOTTOM", 0, -12); c.name:SetWidth(100)
      c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); c.sub:SetPoint("TOP", c.name, "BOTTOM", 0, -2); c.sub:SetWidth(110)
      local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.67, 0.17, 0.08)
      c:SetScript("OnClick", function(self) local who = f.who and f.who[self]; if who then M.Pick(who) end end)
      f.cells[i] = c
    end
    f.who = setmetatable({}, { __mode = "k" })
    local nb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin and C.Skin.Button then C.Skin.Button(nb) end
    nb:SetSize(200, 24); nb:SetPoint("BOTTOM", 0, 14); nb:SetText("Nobody, I found it myself")
    nb:SetScript("OnClick", function() M.Pick(nil) end)
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", 2, 2)
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable"); f.empty:SetPoint("CENTER", 0, -30)
    f.empty:SetText("Group up with the player who showed you Kina, and they'll show up here.")
  end
  local n = #list
  for i, c in ipairs(f.cells) do
    local e = list[i]
    if e then
      c:ClearAllPoints(); c:SetPoint("TOP", f, "TOPLEFT", 220 + (i - (n + 1) / 2) * 104, -168)
      f.who[c] = e.name
      if C.Profile and C.Profile.SetPortrait then pcall(C.Profile.SetPortrait, c.portrait, e.name) end
      local pr = C.Share and C.Share.ProfileOf and C.Share.ProfileOf(e.name)
      local sname = pr and type(pr.stand) == "number" and C.Rep and C.Rep.StandingOf(pr.stand) or "Unproven"
      C.Cos.UpdatePortrait(c.cos, sname, (pr and pr.kinaLv and pr.kinaLv > 0) and pr.kinaLv or 1, pr and pr.recruits)
      if C.Cos.SetFounder then C.Cos.SetFounder(c.cos, pr and pr.dev) end
      c.name:SetText((e.shared and "|cff6ef08c" or "|cffffffff") .. e.name .. "|r")
      local ago = math.floor((C.Now() - (e.seen or C.Now())) / 86400)
      c.sub:SetText((e.shared and "|cff6edc8c" or "") .. (e.here and "In your party" or (ago < 1 and "Met today" or string.format("Met %d day%s ago", ago, ago == 1 and "" or "s")))
        .. (e.shared and " · shared Kina with you|r" or ""))
      if e.shared and i == 1 then c.glow:Show() else c.glow:Hide() end
      c:Show()
    else c:Hide(); f.who[c] = nil end
  end
  f.empty:SetShown(n == 0)
  f:Show()
end
