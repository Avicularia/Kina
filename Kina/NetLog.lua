-- Kina 1.0.8: the network log (Taylor: "I don't have a way to verify the Kina server is
-- working ... I should have a log screen to see what Kina is doing and who it is talking
-- to in real time"). Every addon message Kina sends or receives (group, guild and the
-- Kina network), in plain words, newest first. Memory only: nothing is saved.
-- Open: /kina net, or Settings > Network log.
local ADDON, C = ...
local L = {}
C.NetLogUI = L
local MAX = 400
local lines = {}            -- { t, dir ("in"/"out"/"note"), where, who, what }
local totals = { inN = 0, outN = 0, inB = 0, outB = 0, scansIn = 0, scansOut = 0 }
L.totals = totals
L.lines = lines

-- what a message is, from its first field (group/guild prefix and the Kina network's)
-- (1.0.8 fix: every label read from what Share.lua actually does with each type)
local GROUP = { H = "hello (version, scan ages)", Q = "asks for data", B = "start of a data transfer", M = "AH prices (part of a scan)",
  L = "mob loot records", I = "item info", P = "places", V = "vendor prices", O = "merchant offers", E = "end of a data transfer",
  C = "community drops", T = "note (commendation, record, price hold, data digest)", S = "shared farm log", Z = "farm invite / start / stop",
  X = "farm edit", W = "live farm numbers", K = "a kill in the farm", U = "item used in the farm", Y = "farm split",
  G = "live split numbers", R = "asks for the farm split", F = "Kina Partner farm", N = "recruit credit", A = "recruit thanks",
  J = "recruit claim", D = "Kina Partner request" }
local NET = { P = "here (version)", O = "developer online", V = "version", F = "feedback", R = "feedback answer", K = "feedback receipt",
  H = "feedback hello", M = "feedback mute", PS = "has an AH scan to share", PQ = "asks for that scan",
  PZB = "AH scan: start", PZ = "AH scan: part", PZE = "AH scan: done",
  RN = "relay check-in", W = "note passed on by a relay" }
local function describe(net, msg)
  if net then
    local k = msg:match("^([^|]+)") or "?"
    return NET[k] or ("network message " .. k), k
  end
  local k = msg:match("^(%u)|") or "?"
  return GROUP[k] or ("message " .. k), k
end
L.describe = describe

local function now() return GetTime and GetTime() or 0 end
-- every other Kina heard on any channel: full name (Forever names have a surname), when, how
L.peers = {}
local function mine(name)
  local me = UnitName and UnitName("player") or ""
  local full = C.Net and C.Net.meFull
  if full and name:lower() == full:lower() then return true end
  if full and name:find(" ", 1, true) then return false end -- someone else with your first name
  local first = (name:match("^([^%s%-]+)") or name):lower()
  if first == me:lower() then return true end
  return C.IsMyChar and C.IsMyChar(first) or false
end
local function notePeer(who, where, msg)
  if type(who) ~= "string" or who == "" then return end
  local disp = who:gsub("%-.*$", "")
  if mine(disp) then return end
  local key = (disp:match("^(%S+)") or disp):lower()
  local p = L.peers[key] or {}
  p.name = (#disp > #(p.name or "")) and disp or p.name
  p.t = time and time() or 0
  -- 2.0: every way they were heard, not only the last
  p.vias = p.vias or {}
  p.vias[where] = true
  local v = {}
  for k in pairs(p.vias) do v[#v + 1] = k end
  table.sort(v)
  p.via = table.concat(v, " + ")
  local ver
  if type(msg) == "string" then
    if msg:sub(1, 2) == "H|" then
      local f = {}
      for v in (msg:sub(3) .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
      if f[14] and f[14]:match("^%d+%.%d+%.%d+$") then ver = f[14] end -- the hello's version field
    else ver = msg:match("^V|(%d+%.%d+%.%d+)") end
  end
  if ver then p.ver = ver end
  L.peers[key] = p
end
local function push(dir, where, who, what, bytes)
  -- 2.0: a run of the same kind of message (a scan's parts, a data transfer) is one line
  local top = lines[1]
  local key = (what or ""):gsub("%d+", "#")
  if top and top.dir == dir and top.where == (where or "") and top.who == (who or "") and top.key == key and dir ~= "note" then
    top.n = (top.n or 1) + 1
    top.t = time and time() or 0
    top.what = (what or "") .. "  |cff9d9d9d(x" .. top.n .. ")|r"
    if dir == "in" then totals.inN = totals.inN + 1; totals.inB = totals.inB + (bytes or 0)
    else totals.outN = totals.outN + 1; totals.outB = totals.outB + (bytes or 0) end
    if L.frame and L.frame:IsShown() then L.dirty = true end
    return
  end
  table.insert(lines, 1, { t = time and time() or 0, dir = dir, where = where or "", who = who or "", what = what or "", base = what or "", key = key })
  if #lines > MAX then table.remove(lines) end
  if dir == "in" then totals.inN = totals.inN + 1; totals.inB = totals.inB + (bytes or 0)
  elseif dir == "out" then totals.outN = totals.outN + 1; totals.outB = totals.outB + (bytes or 0) end
  if L.frame and L.frame:IsShown() then L.dirty = true end
end

-- called by Share.lua (group/guild) and Net.lua (Kina network) for every message
function C.NetLog(dir, channel, who, msg, net)
  if type(msg) ~= "string" then return end
  local what = describe(net, msg)
  local where
  if not net then where = (channel or ""):lower()
  elseif channel == "WHISPER" then where = "network, to one Kina"
  elseif channel == "RELAYED" then where = "network (relayed)"
  elseif channel == "RELAY" then where = "relay channel"
  else
    local i = C.Net and C.Net.Which and C.Net.Which(channel)
    where = (type(i) == "number" and i > 1) and ("Kina network " .. string.char(64 + i)) or "Kina network"
  end
  local disp = who and (tostring(who):gsub("%-.*$", "")) or ""
  if dir == "in" then notePeer(disp, where, msg) end
  push(dir, where, disp, what, #msg)
end
-- a plain-words line for something bigger (a whole scan sent or received)
function C.NetNote(text)
  if text:find("scan") and text:find("^got") then totals.scansIn = totals.scansIn + 1 end
  if text:find("scan") and text:find("^sent") then totals.scansOut = totals.scansOut + 1 end
  push("note", "", "", text, 0)
end

------------------------------------------------------------------ the window
local ROWS = 21
local GOLD, GREY, GREEN, BLUE, WHITE = "|cffffc54a", "|cff9d9d9d", "|cff40ff40", "|cff6fb4ff", "|cffffffff"
local function summary()
  local N = C.Net
  local on = N and N.Enabled and N.Enabled()
  local out = {}
  local joined = N and N.Joined and N.Joined()
  out[#out + 1] = GOLD .. "Kina network:|r " .. (not on and ("|cffff6a50off|r (Settings > Kina network)") or (joined and (GREEN .. "on, joined|r" .. GREY .. " (" .. tostring(N.CHANNEL) .. ((N.Relay and N.Relay.IsRelay()) and "; you're relaying it to the other Kina channels" or "") .. ")|r") or ("|cffff6a50on, but not joined yet|r" .. GREY .. " (retrying every 30 s)|r")))
  -- 1.0.8 (Taylor: "showing 1 person online but there's definitely more"): every other Kina
  -- heard on any channel in the last 30 minutes (it used to count only the network, and you)
  local list, t = {}, time and time() or 0
  for _, p in pairs(L.peers) do if t - (p.t or 0) < 1800 then list[#list + 1] = p end end
  table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
  local parts, onNet = {}, 0
  for _, p in ipairs(list) do
    if p.via:find("network") then onNet = onNet + 1 end
    local ago = math.floor((t - p.t) / 60)
    parts[#parts + 1] = WHITE .. p.name .. "|r" .. GREY .. " (" .. (p.ver and ("v" .. p.ver .. ", ") or "") .. p.via .. ", " .. (ago < 1 and "now" or (ago .. "m")) .. ")|r"
  end
  out[#out + 1] = GOLD .. "Other Kinas heard (last 30 min):|r " .. (#list > 0 and (WHITE .. #list .. "|r  " .. table.concat(parts, ", ")) or (GREY .. "none yet|r"))
  -- 2.0: whether the channel really carries your messages (the game sends each one back to you)
  local echo = N and N.lastEcho
  out[#out + 1] = GOLD .. "Channel check:|r " .. (not joined and (GREY .. "not joined|r") or (echo and (t - echo) < 900) and (GREEN .. "working|r" .. GREY .. " (your own messages come back " .. math.floor((t - echo) / 60) .. "m ago, so other Kinas on " .. tostring(N.CHANNEL) .. " hear you)|r") or ("|cffff6a50no echo yet|r" .. GREY .. " (your messages haven't come back: the channel may be refusing them)|r"))
  out[#out + 1] = GREY .. "On the Kina network: " .. onNet .. ". Only Kina 1.0.7 and newer join it (realm-wide prices); older Kinas talk over group and guild only.|r"
  out[#out + 1] = string.format("%sThis session:|r sent %d messages (%.1f KB), received %d (%.1f KB).  AH scans sent %d, received %d.",
    GOLD, totals.outN, totals.outB / 1024, totals.inN, totals.inB / 1024, totals.scansOut, totals.scansIn)
  local sync = C.Share and C.Share.SyncStatus and C.Share.SyncStatus() or ""
  out[#out + 1] = GOLD .. "Right now:|r " .. (sync ~= "" and sync or (GREY .. "nothing moving|r"))
  return table.concat(out, "\n")
end

local function build()
  if L.frame then return L.frame end
  local f = CreateFrame("Frame", "KinaNetLog", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(680, 470); f:SetPoint("CENTER", 0, 40)
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(120); f:SetClampedToScreen(true)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.04, 0.035, 0.03, 0.96); f:SetBackdropBorderColor(0.86, 0.6, 0.2, 1)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 14, -12)
  if C.Cos and C.Cos.Font then C.Cos.Font(title, 15, "") end
  title:SetText(GOLD .. "Kina network log|r"); title:SetTextColor(1, 0.78, 0.34)
  local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -4, -4)
  f.sum = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.sum:SetPoint("TOPLEFT", 14, -36)
  f.sum:SetWidth(650); f.sum:SetJustifyH("LEFT"); f.sum:SetSpacing(3)
  local rule = f:CreateTexture(nil, "ARTWORK"); rule:SetColorTexture(0.52, 0.35, 0.11, 0.9); rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", 12, -124); rule:SetPoint("TOPRIGHT", -12, -124)
  f.rows = {}
  for i = 1, ROWS do
    local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r:SetPoint("TOPLEFT", 14, -130 - (i - 1) * 15); r:SetWidth(650); r:SetJustifyH("LEFT")
    if r.SetWordWrap then r:SetWordWrap(false) end
    f.rows[i] = r
  end
  f.offset = 0
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(self, d)
    self.offset = math.max(0, math.min(math.max(0, #lines - ROWS), self.offset - d * 3)); L.Draw()
  end)
  -- hide the farm chatter (kills, farm log) to see the rest
  local quiet = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate"); quiet:SetSize(22, 22)
  quiet:SetPoint("BOTTOMLEFT", 10, 8)
  local ql = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ql:SetPoint("LEFT", quiet, "RIGHT", 2, 0)
  ql:SetText("Hide farm chatter (kills, farm log)")
  quiet:SetScript("OnClick", function(self) L.quiet = self:GetChecked() and true or false; f.offset = 0; L.Draw() end)
  local tip = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); tip:SetPoint("BOTTOMRIGHT", -14, 13)
  tip:SetText("newest first  |  scroll for older  |  /kina net")
  tinsert(UISpecialFrames, "KinaNetLog")
  local acc = 0
  f:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 1 and not L.dirty then return end
    if acc < 0.25 then return end
    acc = 0; L.dirty = false; L.Draw()
  end)
  f:Hide()
  L.frame = f
  return f
end

local CHATTER = { ["a kill"] = true, ["farm log"] = true, ["farm numbers"] = true, ["relay check-in"] = true }
function L.Draw()
  local f = L.frame
  if not f then return end
  f.sum:SetText(summary())
  local shown = {}
  for _, l in ipairs(lines) do if not (L.quiet and CHATTER[l.base or l.what]) then shown[#shown + 1] = l end end
  for i = 1, ROWS do
    local l = shown[i + f.offset]
    if l then
      local arrow = (l.dir == "out" and (BLUE .. "sent|r")) or (l.dir == "in" and (GREEN .. "got |r")) or (GOLD .. "  * |r")
      local when = date and date("%H:%M:%S", l.t) or ""
      local who = l.who ~= "" and ((l.dir == "out" and " to " or " from ") .. WHITE .. l.who .. "|r") or ""
      if l.dir == "out" and l.who == "" then who = "" end
      local where = l.where ~= "" and (GREY .. "  (" .. l.where .. ")|r") or ""
      f.rows[i]:SetText(GREY .. when .. "|r  " .. arrow .. "  " .. l.what .. who .. where)
    else f.rows[i]:SetText(i == 1 and #shown == 0 and (GREY .. "Nothing sent or received yet this session.|r") or "") end
  end
end

function L.Toggle()
  local f = build()
  if f:IsShown() then f:Hide() else f.offset = 0; f:Show(); f:Raise(); L.Draw() end
end
