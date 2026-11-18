-- Kina feedback (1.0.6, Taylor): players write to the developer from Help > Feedback (or
-- /kina feedback); the developer answers in their own Feedback inbox. Conversations are
-- threads kept on both sides.
--  * a message waits on the writer's PC until the other side is online, then goes as
--    invisible addon messages (Net.lua), never chat; it's marked delivered when the other
--    side's Kina confirms it
--  * the player's Kina says "I'm here" to the developer when it hears they're online, so
--    the developer's Kina can deliver replies (it only ever sends to someone just heard)
--  * an answer gives a toast and a red dot on Help until it's read
-- Messages (prefix KinaNet, to one character):
--   F|tid|seq|part|total|text   a player's message (in pieces)
--   R|tid|seq|part|total|text   the developer's reply
--   K|tid|seq|who               "got it" (who: F or R, whose message)
--   H|n                         a player with threads says hello to the developer
local _, C = ...
local FB = {}
C.Feedback = FB
FB.MAX = 500
local PART = 180

local function db()
  C.db.feedback = type(C.db.feedback) == "table" and C.db.feedback or {}
  local d = C.db.feedback
  d.threads = d.threads or {}
  return d
end
local function N() return C.Net end
local function newId()
  local s = ""
  for _ = 1, 6 do s = s .. string.char(96 + math.random(1, 26)) end
  return s
end
-- a thread: { id, with (the other side), msgs = { {mine, t, text, sent, got} }, unread, done }
local function thread(id, with)
  local d = db()
  local key = (with and (with:lower() .. ":") or "") .. id
  local t = d.threads[key]
  if not t then t = { id = id, with = with, msgs = {}, unread = 0, started = C.Now() }; d.threads[key] = t end
  return t
end
FB.Thread = thread
function FB.Threads()
  local out = {}
  for _, t in pairs(db().threads) do out[#out + 1] = t end
  table.sort(out, function(a, b)
    if (a.unread > 0) ~= (b.unread > 0) then return a.unread > 0 end
    local la, lb = a.msgs[#a.msgs], b.msgs[#b.msgs]
    return (la and la.t or a.started) > (lb and lb.t or b.started)
  end)
  return out
end
function FB.Unread()
  local n = 0
  for _, t in pairs(db().threads) do n = n + (t.unread or 0) end
  return n
end

------------------------------------------------------------------ sending
local function pieces(text)
  local out = {}
  for i = 1, #text, PART do out[#out + 1] = text:sub(i, i + PART - 1) end
  if #out == 0 then out[1] = "" end
  return out
end
-- send a message's pieces to `to` (who must have been heard from just now)
local function deliver(kind, t, seq, m, to)
  local ps = pieces(m.text)
  for i, p in ipairs(ps) do
    if not N().Tell(to, string.format("%s|%s|%d|%d|%d|%s", kind, t.id, seq, i, #ps, p)) then return false end
  end
  m.tries = (m.tries or 0) + 1; m.lastTry = C.Now()
  return true
end
-- anything waiting that can go now
function FB.Flush()
  local Nt = N()
  if not Nt then return end
  local dev = Nt.IAmDeveloper()
  for _, t in pairs(db().threads) do
    for seq, m in ipairs(t.msgs) do
      if m.mine and not m.got and (not m.lastTry or C.Now() - m.lastTry > 120) then
        if dev then
          if t.with and Nt.Heard(t.with) then deliver("R", t, seq, m, t.with) end
        else
          local on, name = Nt.DevOnline()
          if on and name then deliver("F", t, seq, m, name) end
        end
      end
    end
  end
end
-- a new message: a player starts or continues a thread; the developer answers one
function FB.Write(text, t)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil, "write something first" end
  if #text > FB.MAX then text = text:sub(1, FB.MAX) end
  if not t then
    if N().IAmDeveloper() then return nil, "pick a thread to answer" end
    t = thread(newId(), nil)
  end
  table.insert(t.msgs, { mine = true, t = C.Now(), text = text })
  FB.Flush()
  return t
end

------------------------------------------------------------------ receiving
local partial = {}
local function assemble(from, f)
  -- f: kind, tid, seq, part, total, text...
  local tid, seq, part, total = f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
  if not (tid and seq and part and total) or total > 10 then return nil end
  local text = table.concat(f, "|", 6)
  local key = from:lower() .. ":" .. tid .. ":" .. seq
  partial[key] = partial[key] or {}
  partial[key][part] = text
  for i = 1, total do if not partial[key][i] then return nil end end
  local full = table.concat(partial[key], "", 1, total)
  partial[key] = nil
  return tid, seq, full
end
local function receive(from, f, kind)
  local tid, seq, text = assemble(from, f)
  if not tid then return end
  local Nt = N()
  -- the developer files a thread under the player; a player under its own id
  local t
  if kind == "F" then
    if not Nt.IAmDeveloper() then return end
    t = thread(tid, from)
  else
    if not Nt.IsDeveloper(from) then return end -- only the developer answers
    t = db().threads[tid] or thread(tid, nil)
  end
  t.got = t.got or {}
  local mark = kind .. seq
  if not t.got[mark] then
    t.got[mark] = true
    table.insert(t.msgs, { mine = false, t = C.Now(), text = text, from = from })
    t.unread = (t.unread or 0) + 1
    t.done = nil
    if C.Toast and C.Toast.Notice then
      if kind == "R" then C.Toast.Notice("The developer answered your feedback", "Help > Feedback")
      else C.Toast.Notice("New feedback from " .. from, "Help > Feedback") end
    end
    C.Print(kind == "R" and "|cffffc54athe developer answered your feedback.|r Help > Feedback to read it."
      or ("|cffffc54anew feedback from " .. from .. ".|r Help > Feedback."))
  end
  Nt.Tell(from, string.format("K|%s|%d|%s", tid, seq, kind))
  if C.Refresh then C.Refresh() end
end
local function got(from, f)
  local tid, seq, whose = f[2], tonumber(f[3]), f[4]
  local d = db()
  local t = d.threads[tid] or d.threads[from:lower() .. ":" .. tostring(tid)]
  local m = t and seq and t.msgs[seq]
  if m and m.mine then m.got = true; if C.Refresh then C.Refresh() end end
end
local function hello(from)
  if N().IAmDeveloper() then FB.Flush() end
end
function FB.OnDevOnline(name)
  -- tell the developer we're here, so replies can come; then send what's waiting
  local any = next(db().threads) ~= nil
  if any then N().Tell(name, "H|1") end
  FB.Flush()
end
function FB.MarkRead(t) if t then t.unread = 0; if C.Refresh then C.Refresh() end end end

-- 1.0.6 (Taylor): the feedback lives in the shared Drive folder (it's in Kina's saved file
-- there), so Claude can read it and write reply drafts into FeedbackDrafts.lua. A draft
-- shows in your reply box, marked as Claude's; nothing goes out until you press Reply.
-- Drafts are keyed by thread ("player:threadid") and by the message count they answer.
local function threadKey(t) return ((t.with and (t.with:lower() .. ":")) or "") .. t.id end
FB.ThreadKey = threadKey
function FB.Draft(t)
  local all = C.Data and C.Data.feedbackDrafts
  local d = t and all and all[threadKey(t)]
  if not (d and d.text) then return nil end
  local used = db().draftsUsed or {}
  if used[threadKey(t)] == (d.at or #t.msgs) then return nil end
  if d.at and d.at ~= #t.msgs then return nil end -- written for an older state of the thread
  return d.text
end
function FB.DraftUsed(t)
  local all = C.Data and C.Data.feedbackDrafts
  local d = t and all and all[threadKey(t)]
  if not d then return end
  local x = db(); x.draftsUsed = x.draftsUsed or {}
  x.draftsUsed[threadKey(t)] = d.at or #t.msgs
end

C.After(0, function()
  local Nt = N()
  if not Nt then return end
  Nt.On("F", function(from, f) receive(from, f, "F") end)
  Nt.On("R", function(from, f) receive(from, f, "R") end)
  Nt.On("K", got)
  Nt.On("H", hello)
end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() pcall(FB.Flush) end) end

------------------------------------------------------------------ the page (Help > Feedback)
local page
local sel
local function fmtTime(t) return date and date("%b %d %H:%M", t) or tostring(t) end
local function build(parent)
  page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints()
  page.status = C.Text(page, "OVERLAY", "GameFontHighlight"); page.status:SetPoint("TOPLEFT", 0, 0); page.status:SetJustifyH("LEFT")
  page.list = {}
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(b) end
    b:SetSize(170, 22); b:SetPoint("TOPLEFT", 0, -30 - (i - 1) * 26)
    b:SetScript("OnClick", function(self) sel = self.thread; FB.MarkRead(sel); FB.Draw() end)
    page.list[i] = b
  end
  page.new = CreateFrame("Button", nil, page, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(page.new) end
  page.new:SetSize(170, 24); page.new:SetPoint("TOPLEFT", 0, -30 - 8 * 26 - 6); page.new:SetText("New message")
  page.new:SetScript("OnClick", function() sel = nil; FB.Draw() end)
  page.view = C.Text(page, "OVERLAY", "GameFontHighlight"); page.view:SetPoint("TOPLEFT", 190, -30); page.view:SetPoint("RIGHT", page, "RIGHT", -6, 0)
  page.view:SetJustifyH("LEFT"); page.view:SetJustifyV("TOP"); if page.view.SetWordWrap then page.view:SetWordWrap(true) end
  local eb = CreateFrame("EditBox", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
  eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetMaxLetters(FB.MAX); eb:SetFontObject(C.Font and C.Font("GameFontHighlight") or "GameFontHighlight")
  eb:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 190, 40); eb:SetPoint("RIGHT", page, "RIGHT", -6, 0); eb:SetHeight(80)
  if eb.SetBackdrop then eb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    eb:SetBackdropColor(0, 0, 0, 0.45); eb:SetBackdropBorderColor(0.94, 0.57, 0.03, 0.6) end
  eb:SetTextInsets(6, 6, 6, 6)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  page.edit = eb
  page.send = CreateFrame("Button", nil, page, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(page.send) end
  page.send:SetSize(110, 24); page.send:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 8)
  page.send:SetScript("OnClick", function()
    if page.fromDraft then FB.DraftUsed(sel) end
    local t, err = FB.Write(eb:GetText(), sel)
    if not t then C.Print(err); return end
    page.fromDraft = nil
    sel = t; eb:SetText(""); eb:ClearFocus(); FB.Draw()
  end)
  page.draftNote = C.Text(page, "OVERLAY", "GameFontNormalSmall"); page.draftNote:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 4)
  page.discard = CreateFrame("Button", nil, page, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(page.discard) end
  page.discard:SetSize(110, 20); page.discard:SetPoint("BOTTOMRIGHT", eb, "TOPRIGHT", 0, 2); page.discard:SetText("Discard draft")
  page.discard:SetScript("OnClick", function() FB.DraftUsed(sel); page.fromDraft = nil; eb:SetText(""); FB.Draw() end)
  page.done = CreateFrame("Button", nil, page, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(page.done) end
  page.done:SetSize(110, 24); page.done:SetPoint("RIGHT", page.send, "LEFT", -6, 0)
  page.done:SetScript("OnClick", function() if sel then sel.done = not sel.done; FB.Draw() end end)
  page.count = C.Text(page, "OVERLAY", "GameFontDisableSmall"); page.count:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 190, 14)
  eb:SetScript("OnTextChanged", function(self) page.count:SetText(#(self:GetText() or "") .. " / " .. FB.MAX) end)
end
function FB.Draw()
  if not (page and page:IsShown()) then return end
  local Nt = N()
  local dev = Nt.IAmDeveloper()
  local on = Nt.DevOnline()
  page.status:SetText(dev and "|cffffc54aYour feedback inbox.|r Players see you online while you're on."
    or (on and "|cff3fd03fThe developer is online now.|r Messages go straight to them."
    or "|cff9d9d9dThe developer is offline.|r Write anyway: Kina sends it when they're next online."))
  local ts = FB.Threads()
  for i, b in ipairs(page.list) do
    local t = ts[i]
    b.thread = t
    if t then
      local first = t.msgs[1] and t.msgs[1].text or "(empty)"
      local label = (dev and (t.with or "?") .. ": " or "") .. first:sub(1, 18)
      if (t.unread or 0) > 0 then label = "|cffff4040*|r " .. label end
      if t.done then label = "|cff9d9d9d" .. label .. "|r" end
      b:SetText(label); b:Show()
      if t == sel then b:LockHighlight() else b:UnlockHighlight() end
    else b:Hide() end
  end
  page.new:SetShown(not dev)
  local lines = {}
  if sel then
    for _, m in ipairs(sel.msgs) do
      local who = m.mine and "|cffffc54aYou|r" or (dev and ("|cff78beff" .. (m.from or sel.with or "?") .. "|r") or "|cffff9933The developer|r")
      local state = m.mine and (m.got and " |cff3fd03fdelivered|r" or " |cff9d9d9dwaiting to send|r") or ""
      lines[#lines + 1] = string.format("%s  |cff9d9d9d%s|r%s\n%s", who, fmtTime(m.t), state, m.text)
    end
    page.send:SetText(dev and "Reply" or "Send")
    page.done:SetShown(dev); page.done:SetText(sel.done and "Reopen" or "Done")
  else
    lines[1] = dev and "|cff9d9d9dPick a thread on the left to read it and answer.|r"
      or "|cff9d9d9dBugs, ideas, requests: write below and press Send. Up to " .. FB.MAX .. " letters.|r"
    page.send:SetText("Send"); page.done:Hide()
  end
  page.view:SetText(table.concat(lines, "\n\n"))
  -- Claude's draft for this thread, into the reply box once (you edit or send it)
  local draft = dev and sel and FB.Draft(sel)
  if draft and page.draftFor ~= sel then
    page.draftFor = sel; page.fromDraft = true
    page.edit:SetText(draft)
  elseif not draft then page.fromDraft = page.fromDraft and page.draftFor == sel or nil end
  page.draftNote:SetText(page.fromDraft and "|cff78beffDraft from Claude: edit it, then Reply.|r" or "")
  page.discard:SetShown(page.fromDraft and true or false)
  page.edit:SetShown(not (dev and not sel)); page.send:SetShown(not (dev and not sel))
end
-- Help shows it as a page (returns the height it uses)
function FB.Show(child, w)
  if not page then build(child) end
  page:SetParent(child); page:ClearAllPoints(); page:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); page:SetSize(w, 420)
  page:Show()
  FB.Draw()
  return 420
end
function FB.Hide() if page then page:Hide() end end

------------------------------------------------------------------ the red dot on Help
local dot
local function badge()
  local u = C.ui
  local b = u and u.tabButtons and u.tabButtons["Help"]
  if not b then return end
  if not dot then
    dot = CreateFrame("Frame", nil, b); dot:SetSize(14, 14); dot:SetPoint("TOPRIGHT", b, "TOPRIGHT", 4, 4)
    local t = dot:CreateTexture(nil, "OVERLAY"); t:SetAllPoints(); t:SetColorTexture(0.9, 0.12, 0.1, 1)
    dot.n = dot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); dot.n:SetPoint("CENTER")
  end
  local n = FB.Unread()
  dot.n:SetText(n > 9 and "9+" or tostring(n))
  dot:SetShown(n > 0)
end
FB.Badge = badge
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() pcall(badge); pcall(FB.Draw); pcall(FB.DrawPop) end) end

------------------------------------------------------------------ the feedback window
-- 1.0.6 (Taylor, approved mock): a player clicks the developer's badge (top of the Kina
-- window) and this opens: the developer's portrait with their cosmetics, "Online now",
-- the conversation as bubbles, and a box to write in with Bug / Idea / Request / Other.
-- The developer's own click opens their inbox (Help > Feedback) instead.
local pop
local TAGS = { "Bug", "Idea", "Request", "Other" }
local GOLD, BLUE, GREEN, MUTED = "|cffffc54a", "|cff78b4ff", "|cff3fd03f", "|cff9d9d9d"
-- every message between you and the developer, oldest first
local function conversation()
  local out = {}
  for _, t in pairs(db().threads) do
    if not t.with then for _, m in ipairs(t.msgs) do out[#out + 1] = m end end
  end
  table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
  return out
end
-- the thread new messages go to: your latest, unless it's over a week old
local function currentThread()
  local best
  for _, t in pairs(db().threads) do
    if not t.with then
      local last = t.msgs[#t.msgs]
      if not best or (last and last.t or 0) > ((best.msgs[#best.msgs] or {}).t or 0) then best = t end
    end
  end
  if best and best.msgs[#best.msgs] and C.Now() - best.msgs[#best.msgs].t < 7 * 86400 then return best end
  return nil
end
local function bubbleFrame(parent)
  local b = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if b.SetBackdrop then b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }) end
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); b.text:SetPoint("TOPLEFT", 10, -8); b.text:SetJustifyH("LEFT")
  if b.text.SetWordWrap then b.text:SetWordWrap(true) end
  b.meta = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); b.meta:SetPoint("BOTTOMRIGHT", -8, 5)
  b.face = CreateFrame("Frame", nil, parent); b.face:SetSize(30, 30)
  b.faceTex = b.face:CreateTexture(nil, "ARTWORK"); b.faceTex:SetAllPoints()
  b.faceTex:SetTexture("Interface\\AddOns\\Kina\\Media\\KinaLogo")
  return b
end
local function buildPop()
  local f = CreateFrame("Frame", "KinaFeedbackPop", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(500, 560); f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
  f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if C.Skin and C.Skin.On and C.Skin.On() and C.Skin.Frame then C.Skin.Frame(f, 20) elseif f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.08, 0.06, 0.045, 0.98); f:SetBackdropBorderColor(0.85, 0.63, 0.24)
  end
  -- header glow behind the portrait
  local glow = f:CreateTexture(nil, "BACKGROUND", nil, 2); glow:SetSize(260, 260); glow:SetPoint("CENTER", f, "TOPLEFT", 78, -78)
  glow:SetTexture("Interface\\AddOns\\Kina\\Media\\Cos\\fx_rays"); glow:SetBlendMode("ADD"); glow:SetVertexColor(1, 0.75, 0.35, 0.28)
  -- the developer's portrait, with their cosmetics
  f.pbox = CreateFrame("Frame", nil, f); f.pbox:SetSize(84, 84); f.pbox:SetPoint("TOPLEFT", 36, -36)
  f.ptex = f.pbox:CreateTexture(nil, "ARTWORK")
  if C.Cos and C.Cos.Portrait then local ok, o = pcall(C.Cos.Portrait, f.pbox, f.ptex, { model = true }); if ok then f.cos = o end end
  f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.name:SetPoint("TOPLEFT", f.pbox, "TOPRIGHT", 34, 4)
  if C.Cos and C.Cos.Font then C.Cos.Font(f.name, 24, "OUTLINE") end
  f.titles = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.titles:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
  f.pill = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil); f.pill:SetSize(112, 22); f.pill:SetPoint("TOPLEFT", f.titles, "BOTTOMLEFT", 0, -8)
  if f.pill.SetBackdrop then f.pill:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f.pill:SetBackdropColor(0.08, 0.24, 0.11, 1); f.pill:SetBackdropBorderColor(0.31, 0.86, 0.39, 1) end
  local dot = f.pill:CreateTexture(nil, "OVERLAY"); dot:SetSize(10, 10); dot:SetPoint("LEFT", 8, 0); dot:SetTexture("Interface\\COMMON\\Indicator-Green")
  f.pillText = f.pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.pillText:SetPoint("LEFT", dot, "RIGHT", 5, 0)
  f.invite = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.invite:SetPoint("TOPLEFT", f.pill, "BOTTOMLEFT", 0, -8); f.invite:SetPoint("RIGHT", f, "RIGHT", -20, 0)
  f.invite:SetJustifyH("LEFT"); f.invite:SetText("|cffe8d6a0Bugs, ideas, requests: I read every one and answer here.|r")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
  local line1 = f:CreateTexture(nil, "ARTWORK"); line1:SetHeight(1); line1:SetPoint("TOPLEFT", 16, -152); line1:SetPoint("TOPRIGHT", -16, -152); line1:SetColorTexture(0.55, 0.41, 0.18, 1)
  -- the conversation
  f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.head:SetPoint("TOPLEFT", 20, -162)
  if C.Cos and C.Cos.Font then C.Cos.Font(f.head, 15, "") end
  f.head:SetText(GOLD .. "Your messages|r")
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.sub:SetPoint("TOPRIGHT", -22, -166)
  local sf = CreateFrame("ScrollFrame", "KinaFeedbackPopScroll", f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, -184); sf:SetPoint("BOTTOMRIGHT", -36, 214)
  if C.Skin and C.Skin.HideTemplate then pcall(C.Skin.HideTemplate, sf) end
  f.child = CreateFrame("Frame", nil, sf); f.child:SetSize(440, 10); sf:SetScrollChild(f.child)
  f.sf = sf; f.bubbles = {}
  f.empty = f.child:CreateFontString(nil, "OVERLAY", "GameFontDisable"); f.empty:SetPoint("TOP", 0, -30)
  f.empty:SetText("No messages yet. Write the first one below.")
  -- writing
  local line2 = f:CreateTexture(nil, "ARTWORK"); line2:SetHeight(1); line2:SetPoint("BOTTOMLEFT", 16, 204); line2:SetPoint("BOTTOMRIGHT", -16, 204); line2:SetColorTexture(0.55, 0.41, 0.18, 1)
  f.newHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.newHead:SetPoint("BOTTOMLEFT", 20, 176)
  if C.Cos and C.Cos.Font then C.Cos.Font(f.newHead, 15, "") end
  f.newHead:SetText(GOLD .. "New message|r")
  f.tag = "Bug"; f.tagB = {}
  for i, t in ipairs(TAGS) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(b) end
    b:SetSize(72, 22); b:SetPoint("BOTTOMLEFT", 150 + (i - 1) * 78, 172); b:SetText(t)
    b:SetScript("OnClick", function() f.tag = t; FB.DrawPop() end)
    f.tagB[t] = b
  end
  local eb = CreateFrame("EditBox", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetMaxLetters(FB.MAX); eb:SetFontObject(C.Font and C.Font("GameFontHighlight") or "GameFontHighlight")
  eb:SetPoint("BOTTOMLEFT", 20, 62); eb:SetPoint("BOTTOMRIGHT", -20, 62); eb:SetHeight(100); eb:SetTextInsets(8, 8, 8, 8)
  if eb.SetBackdrop then eb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    eb:SetBackdropColor(0.03, 0.025, 0.02, 0.92); eb:SetBackdropBorderColor(0.78, 0.57, 0.2, 1) end
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.count:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -8, 6)
  eb:SetScript("OnTextChanged", function(self) f.count:SetText(#(self:GetText() or "") .. " / " .. FB.MAX) end)
  f.edit = eb
  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.note:SetPoint("BOTTOMLEFT", 20, 26)
  f.send = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(f.send) end
  f.send:SetSize(120, 30); f.send:SetPoint("BOTTOMRIGHT", -20, 18); f.send:SetText("Send")
  f.send:SetScript("OnClick", function()
    local text = (eb:GetText() or ""):gsub("^%s+", "")
    if text == "" then C.Print("write something first."); return end
    local t, err = FB.Write("[" .. f.tag .. "] " .. text, currentThread())
    if not t then C.Print(err); return end
    eb:SetText(""); eb:ClearFocus(); FB.DrawPop()
  end)
  tinsert(UISpecialFrames, "KinaFeedbackPop")
  f:SetScript("OnShow", function() FB.DrawPop() end)
  f:Hide()
  return f
end
function FB.DrawPop()
  if not (pop and pop:IsShown()) then return end
  local Nt = N()
  local on, name = Nt.DevOnline()
  local look = Nt.devLook or {}
  pop.name:SetText(GOLD .. (name or Nt.devName or Nt.DEVELOPERS[1] or "The developer") .. "|r")
  pop.titles:SetText(BLUE .. "Kina developer  ·  Kina Founder" .. (look.standing and ("  ·  " .. look.standing) or "")
    .. (look.level and C.Rep and C.Rep.Roman and ("  ·  Kina " .. C.Rep.Roman(look.level)) or "") .. "|r")
  pop.pill:SetShown(on and true or false)
  pop.pillText:SetText(GREEN .. "Online now|r")
  if pop.cos and C.Cos.UpdatePortrait then
    pcall(C.Cos.UpdatePortrait, pop.cos, look.standing or "Unproven", look.level or 1, look.recruits or 0)
    if C.Cos.SetFounder then pcall(C.Cos.SetFounder, pop.cos, true) end
    if C.Cos.SetBond then pcall(C.Cos.SetBond, pop.cos, look.bond) end
  end
  if look.class and C.Profile and C.Profile.ClassIcon then pcall(C.Profile.ClassIcon, pop.ptex, look.class) end
  for t, b in pairs(pop.tagB) do if t == pop.tag then b:LockHighlight() else b:UnlockHighlight() end end
  -- the bubbles
  local msgs = conversation()
  local w = (pop.sf:GetWidth() or 440) - 4
  pop.child:SetWidth(w)
  local y = -6
  for i, m in ipairs(msgs) do
    local b = pop.bubbles[i] or bubbleFrame(pop.child); pop.bubbles[i] = b
    local bw = math.floor(w * 0.72)
    b.text:SetWidth(bw - 20); b.text:SetText(m.text)
    local h = (b.text:GetStringHeight() or 14) + 30
    b:SetSize(bw, h); b:ClearAllPoints()
    if m.mine then
      b:SetPoint("TOPRIGHT", pop.child, "TOPRIGHT", -2, y)
      if b.SetBackdropColor then b:SetBackdropColor(0.27, 0.2, 0.09, 0.95); b:SetBackdropBorderColor(0.78, 0.59, 0.24, 1) end
      b.meta:SetText(MUTED .. "you  ·  " .. fmtTime(m.t) .. "  ·  |r" .. (m.got and (GREEN .. "delivered|r") or (MUTED .. "waiting to send|r")))
      b.face:Hide()
    else
      b:SetPoint("TOPLEFT", pop.child, "TOPLEFT", 40, y)
      if b.SetBackdropColor then b:SetBackdropColor(0.11, 0.125, 0.165, 0.95); b:SetBackdropBorderColor(0.43, 0.55, 0.75, 1) end
      b.meta:SetText(MUTED .. (m.from or "developer") .. "  ·  " .. fmtTime(m.t) .. "|r")
      b.face:ClearAllPoints(); b.face:SetPoint("TOPLEFT", pop.child, "TOPLEFT", 2, y - 2); b.face:Show()
    end
    b:Show()
    y = y - h - 10
  end
  for i = #msgs + 1, #pop.bubbles do pop.bubbles[i]:Hide(); pop.bubbles[i].face:Hide() end
  pop.child:SetHeight(math.max(20, -y))
  pop.empty:SetShown(#msgs == 0)
  local unread = 0
  for _, t in pairs(db().threads) do if not t.with then unread = unread + (t.unread or 0); t.unread = 0 end end
  pop.sub:SetText(#msgs > 0 and (MUTED .. #msgs .. " message" .. (#msgs == 1 and "" or "s") .. "|r") or "")
  pop.note:SetText(on and (GREEN .. "They're online: it goes straight to them.|r") or "If they're offline, it waits on your PC and sends when they're back.")
  if pop.sf.SetVerticalScroll and pop.sf.GetVerticalScrollRange then pop.sf:SetVerticalScroll(pop.sf:GetVerticalScrollRange() or 0) end
end
function FB.OpenPopup()
  if N().IAmDeveloper() then
    C.Toggle("Help"); if C.ShowHelpTopic then C.ShowHelpTopic("Feedback") end
    return
  end
  pop = pop or buildPop()
  pop:Show(); pop:Raise(); FB.DrawPop()
end
FB.PopShown = function() return pop ~= nil and pop:IsShown() end
