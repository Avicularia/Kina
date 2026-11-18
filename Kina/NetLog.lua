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
local GROUP = { H = "hello (who's here, scan ages)", M = "AH prices (part of a scan)", B = "start of a data transfer",
  E = "end of a data transfer", Q = "asks for data", L = "mob loot records", V = "vendor prices", O = "merchant prices",
  C = "community drops", K = "a kill", S = "farm log", Z = "farm start/stop", W = "farm numbers", X = "farm note",
  U = "item used", G = "farm split", R = "farm record", T = "debt / payment note", P = "price hold", N = "news" }
local NET = { O = "developer online", V = "version", F = "feedback", R = "feedback answer", K = "feedback receipt",
  H = "feedback hello", M = "feedback mute", PS = "has an AH scan to share", PQ = "asks for that scan",
  PZB = "AH scan: start", PZ = "AH scan: part", PZE = "AH scan: done" }
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
local function push(dir, where, who, what, bytes)
  table.insert(lines, 1, { t = time and time() or 0, dir = dir, where = where or "", who = who or "", what = what or "" })
  if #lines > MAX then table.remove(lines) end
  if dir == "in" then totals.inN = totals.inN + 1; totals.inB = totals.inB + (bytes or 0)
  elseif dir == "out" then totals.outN = totals.outN + 1; totals.outB = totals.outB + (bytes or 0) end
  if L.frame and L.frame:IsShown() then L.dirty = true end
end

-- called by Share.lua (group/guild) and Net.lua (Kina network) for every message
function C.NetLog(dir, channel, who, msg, net)
  if type(msg) ~= "string" then return end
  local what = describe(net, msg)
  local where = net and (channel == "WHISPER" and "network, to one Kina" or "Kina network") or ((channel or ""):lower())
  push(dir, where, who and (Ambiguate and Ambiguate(who, "short") or who) or "", what, #msg)
end
-- a plain-words line for something bigger (a whole scan sent or received)
function C.NetNote(text)
  if text:find("scan") and text:find("^got") then totals.scansIn = totals.scansIn + 1 end
  if text:find("scan") and text:find("^sent") then totals.scansOut = totals.scansOut + 1 end
  push("note", "", "", text, 0)
end

------------------------------------------------------------------ the window
local ROWS = 22
local GOLD, GREY, GREEN, BLUE, WHITE = "|cffffc54a", "|cff9d9d9d", "|cff40ff40", "|cff6fb4ff", "|cffffffff"
local function summary()
  local N = C.Net
  local on = N and N.Enabled and N.Enabled()
  local out = {}
  out[#out + 1] = GOLD .. "Kina network:|r " .. (on and (GREEN .. "on|r") or ("|cffff6a50off|r (Settings > Kina network)"))
  local who = {}
  if N and N.heard then
    local t = C.Now()
    for name, at in pairs(N.heard) do if t - at < 300 then who[#who + 1] = name end end
  end
  table.sort(who)
  out[#out + 1] = GOLD .. "Kinas heard on the network (last 5 min):|r " .. (#who > 0 and (WHITE .. #who .. "|r  " .. GREY .. table.concat(who, ", "):sub(1, 140) .. "|r") or (GREY .. "none yet|r"))
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
  rule:SetPoint("TOPLEFT", 12, -104); rule:SetPoint("TOPRIGHT", -12, -104)
  f.rows = {}
  for i = 1, ROWS do
    local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r:SetPoint("TOPLEFT", 14, -110 - (i - 1) * 15); r:SetWidth(650); r:SetJustifyH("LEFT")
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

local CHATTER = { ["a kill"] = true, ["farm log"] = true, ["farm numbers"] = true }
function L.Draw()
  local f = L.frame
  if not f then return end
  f.sum:SetText(summary())
  local shown = {}
  for _, l in ipairs(lines) do if not (L.quiet and CHATTER[l.what]) then shown[#shown + 1] = l end end
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
