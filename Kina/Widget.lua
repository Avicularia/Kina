-- Kina: farm widget (P1.0.2 redesign).
-- Header: mode chip (SOLO / DUO / PAUSED / SYNCING) and SND, %, x.
-- Hero: gold per hour, big; clock and timer beside it.
-- Tiles: NET, COIN, LOOT, KILLS. Best drop with its icon (it flashes on a big drop).
-- Pay / Ask row after a split, then Start/Stop, Pause, Log, Kina.
-- Start plays the "gates open" fanfare; Stop (by hand or timer) plays the
-- "city cheers" finale. SND turns both off; % changes the background.
local _, C = ...
local floor = math.floor
local W, H = 300, 212
local w -- the widget frame

local GOLD = { 0.96, 0.78, 0.30 }
local BG = { 0.03, 0.05, 0.11 }
local TILE = { 0.07, 0.10, 0.20 }

local function clock(sec)
  sec = math.max(0, floor(sec or 0))
  return string.format("%d:%02d:%02d", floor(sec / 3600), floor(sec / 60) % 60, sec % 60)
end
local function signed(cp)
  if not cp then return "--" end
  return (cp < 0 and "|cffff6060-" or "|cff7CFC00+") .. C.Money(math.abs(cp)) .. "|r"
end
local function text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end
local function tip(btn, title, body) if C.ButtonTip then C.ButtonTip(btn, title, body) end end
local function smallButton(parent, label, width, onClick, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height or 18); b:SetText(label); b:SetScript("OnClick", onClick)
  if b.GetFontString and b:GetFontString() then b:GetFontString():SetFontObject("GameFontHighlightSmall") end
  return b
end

local PRESETS = { 0, 3600, 7200, 10800, 14400 }
local function presetText(sec) return (sec and sec > 0) and (floor(sec / 3600) .. "h timer") or "no timer" end

-- best single drop this session by value
local function bestDrop(s)
  local bestID, bestV, bestN = nil, 0, 0
  -- 1.0.10: a shared farm's best drop comes from the shared log (priced by the leader),
  -- so every widget shows the same one
  if s.sync and s.sync.chain then
    local ex = C.FarmSync and C.FarmSync.Excluded and C.FarmSync.Excluded(s.sync) or {}
    local cnt, val = {}, {}
    for _, ev in ipairs(s.sync.chain) do
      if ev.kind == "L" and not ex[ev.seq] then
        local id, n, _, v = (ev.data or ""):match("^(%d*):(%d*):([^:]*):(%-?%d*)$")
        id, n, v = tonumber(id), tonumber(n) or 1, tonumber(v) or 0
        if id then cnt[id] = (cnt[id] or 0) + n; val[id] = (val[id] or 0) + n * v end
      end
    end
    for id, v in pairs(val) do if v > bestV then bestID, bestV, bestN = id, v, cnt[id] end end
    return bestID, bestV, bestN
  end
  for id, n in pairs(s.items or {}) do
    local v = (C.FarmValue and C.FarmValue(id) or 0) * n
    if v > bestV then bestID, bestV, bestN = id, v, n end
  end
  return bestID, bestV, bestN
end
C.Widget = C.Widget or {}
C.Widget.BestDrop = function(s) return (bestDrop(s)) end
local function itemIcon(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemIconByID then local ok, t = pcall(C_Item.GetItemIconByID, id); if ok and t then return t end end
  if GetItemIcon then local ok, t = pcall(GetItemIcon, id); if ok then return t end end
end

local function applyAlpha()
  if w and w.bg then w.bg:SetColorTexture(BG[1], BG[2], BG[3], C.settings.widgetAlpha or 0.85) end
end

-- the four stat tiles
local function setTile(t, value, sub)
  t.value:SetText(value or "--")
  t.sub:SetText(sub or "")
end

local function refreshPay()
  local due = C.PayDue and C.PayDue()
  if not due then
    -- you are owed: ask the payer to settle (they get a Pay popup)
    local rcv = C.ReceiveDue and C.ReceiveDue()
    if not rcv then w.pay:Hide(); return end
    local near = C.PayInRange and C.PayInRange({ to = rcv.from })
    local who = C.Books.Name(rcv.from)
    w.pay:SetText((near and "Ask " or "|cff9d9d9dAsk ") .. who .. " for " .. C.Money(rcv.amt) .. (near and "" or " (far)|r"))
    w.pay.rcv = rcv
    if near then w.pay:Enable() else w.pay:Disable() end
    w.pay:Show(); return
  end
  w.pay.rcv = nil
  local near = C.PayInRange and C.PayInRange(due)
  local who = C.Books.Name(due.to)
  w.pay:SetText((near and "Pay " or "|cff9d9d9dPay ") .. who .. " " .. C.Money(due.amt) .. (near and "" or " (far)|r"))
  if near then w.pay:Enable() else w.pay:Disable() end
  w.pay:Show()
end

local lastBest -- flash the best-drop line when a new top drop lands
local function showBest(s)
  local id, v, n = nil, 0, 0
  if s then id, v, n = bestDrop(s) end
  if id then
    local r = C.Item(id)
    w.bestIcon:SetTexture(itemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark"); w.bestIcon:Show()
    w.best:SetText(string.format("|cff9d9d9dBest|r  %s%s  |cffffd100%s|r", (r and r.name or ("item " .. id)):sub(1, 22), n > 1 and (" x" .. n) or "", C.Money(v)))
    if lastBest and lastBest ~= id and v >= 10000 then w.flash = 1.5 end
    lastBest = id
  else
    w.bestIcon:Hide(); w.best:SetText(s and "|cff9d9d9dNo drops yet|r" or "")
    lastBest = nil
  end
end

local function chip(textv, r, g, b)
  w.chip.text:SetText(textv)
  w.chip.bg:SetColorTexture(r, g, b, 0.9)
  w.chip:SetWidth(math.max(40, (w.chip.text:GetStringWidth() or 30) + 12))
end

function C.RefreshWidget()
  if not (w and w:IsShown()) then return end
  pcall(refreshPay)
  local s = C.session
  w.snd:SetText(C.settings.farmSound == false and "|cff888888SND|r" or "SND")
  if w.rep and C.RepLine then pcall(function() w.rep.text:SetText(C.RepLine() .. (C.ShareData() and "" or " |cff888888paused|r")) end) end
  w.timer:SetText(presetText(C.settings.farmPreset))
  if s and C.FarmView then
    local v, group, leader = C.FarmView()
    if group then
      w.go:SetText("|cffff8080Stop|r"); w.pause:SetText(s.paused and "Resume" or "Pause")
      if v then
        local secs = math.max(1, v.secs)
        if v.paused then chip("PAUSED", 0.55, 0.42, 0.05) elseif v.behind then chip("SYNCING", 0.45, 0.35, 0.05) else
          local n = 0; for _ in pairs(v.members or {}) do n = n + 1 end
          chip(n > 2 and "GROUP" or "DUO", 0.10, 0.35, 0.15)
        end
        w.clock:SetText((v.paused and "|cffffd100" or "|cffffffff") .. clock(secs) .. "|r")
        w.rate:SetText(secs >= 30 and (C.Money(v.net * 3600 / secs)) or "|cff9d9d9dmeasuring|r")
        w.rateSub:SetText("per hour, group" .. (v.noSplit and " |cffffd100no split|r" or "") .. "  |cff9d9d9d" .. ((s.label or "farm"):sub(1, v.noSplit and 10 or 16)) .. "|r")
        setTile(w.tNet, signed(v.net), "same for all")
        setTile(w.tCoin, C.Money(v.coin or 0), "game split")
        setTile(w.tLoot, C.Money(v.items or 0), ((v.used or 0) > 0) and ("used " .. C.Money(v.used)) or "split prices")
        setTile(w.tKills, tostring(v.kills or 0), secs >= 60 and string.format("%d / hour", (v.kills or 0) * 3600 / secs) or "")
        if s.sync then w.status:SetText("|cff9d9d9dcounted by " .. tostring(leader) .. "|r")
        -- 1.0.10: the farm started before Kina saw your partner's Kina: it isn't shared, and
        -- their loot only counts when they loot near you
        else w.status:SetText("|cffff8040not shared: Stop, then Start again to share|r") end
      else
        chip("WAITING", 0.45, 0.35, 0.05)
        w.clock:SetText("|cff9d9d9d" .. clock(C.SessionSecs(s)) .. "|r")
        w.rate:SetText("|cff9d9d9d...|r"); w.rateSub:SetText("waiting for " .. tostring(leader) .. "'s numbers")
        for _, t in ipairs({ w.tNet, w.tCoin, w.tLoot, w.tKills }) do setTile(t, "--", "") end
        w.status:SetText("")
      end
      showBest(s)
      return
    end
  end
  if s then
    local sum = C.SessionSummary(s)
    local secs = C.SessionSecs(s)
    if s.paused then chip("PAUSED", 0.55, 0.42, 0.05) else chip("SOLO", 0.12, 0.25, 0.50) end
    w.clock:SetText((s.paused and "|cffffd100" or "|cffffffff") .. clock(secs) .. "|r")
    w.rate:SetText(secs >= 30 and C.Money(sum.perHour) or "|cff9d9d9dmeasuring|r")
    w.rateSub:SetText("per hour  |cff9d9d9d" .. ((s.label or "farm"):sub(1, 20)) .. "|r")
    setTile(w.tNet, signed(sum.total), ((sum.used or 0) > 0) and ("used " .. C.Money(sum.used)) or "what you looted")
    setTile(w.tCoin, C.Money(sum.cash or 0), ((s.money.pickpocket or 0) > 0) and ("picks " .. C.Money(s.money.pickpocket)) or "looted coin")
    local extra = {}
    if (s.skins or 0) > 0 then extra[#extra + 1] = s.skins .. " skins" end
    if (s.nodes or 0) > 0 then extra[#extra + 1] = s.nodes .. " nodes" end
    setTile(w.tLoot, C.Money(sum.items or 0), table.concat(extra, ", "))
    setTile(w.tKills, tostring(sum.kills or 0), secs >= 60 and string.format("%d / hour", (sum.kills or 0) * 3600 / secs) or "")
    w.status:SetText(s.limit and ("|cffbbbbbbtimer ends in " .. clock(s.limit - secs) .. "|r") or "")
    w.go:SetText("|cffff8080Stop|r"); w.pause:SetText(s.paused and "Resume" or "Pause")
    showBest(s)
  else
    chip("READY", 0.20, 0.20, 0.25)
    w.pause:SetText("Pause")
    local last = C.db.sessions[1]
    w.clock:SetText("|cff9d9d9d" .. clock(last and ((last.gview and last.gview.secs) or (last.result and last.result.secs)) or 0) .. "|r")
    local g = last and (last.gview or last.result)
    local net = g and ((type(g.net) == "number" and g.net) or g.total) or 0
    local secs = g and math.max(1, g.secs or 1) or 1
    if g then
      w.rate:SetText("|cffbbbbbb" .. C.Money(net * 3600 / secs) .. "|r")
      w.rateSub:SetText("last farm  |cff9d9d9d" .. ((last.label or "?"):sub(1, 18)) .. ", " .. (last.why or "stopped") .. "|r")
      setTile(w.tNet, signed(net), last.gview and "group" or "")
      setTile(w.tCoin, C.Money((last.gview and last.gview.coin) or (last.result and last.result.cash) or 0), "")
      setTile(w.tLoot, C.Money((last.gview and last.gview.items) or (last.result and last.result.items) or 0), "")
      setTile(w.tKills, tostring(g.kills or 0), "")
    else
      w.rate:SetText("|cff9d9d9d--|r"); w.rateSub:SetText("press Start when you begin farming")
      for _, t in ipairs({ w.tNet, w.tCoin, w.tLoot, w.tKills }) do setTile(t, "--", "") end
    end
    local tr = last and last.split and last.split.loot and last.split.transfers
    if tr and tr[1] then
      -- what's still open between you and the group on that farm (part payments count)
      local r = C.Books and C.Books.Farm(last)
      local open = {}
      for _, d in ipairs(r and r.debts or {}) do if d.amt - d.done >= 1 then open[#open + 1] = d end end
      -- name the same person the Pay / Ask button does
      local tgt = C.PayDue and C.PayDue(); tgt = tgt and tgt.to or (C.ReceiveDue and C.ReceiveDue() or {}).from
      local d = open[1]
      for _, o in ipairs(open) do if tgt and C.Books.Name(o.who) == C.Books.Name(tgt) then d = o; break end end
      if d then
        local left = C.Money(math.floor(d.amt - d.done))
        local more = #open > 1 and string.format(" |cff9d9d9d(+%d more)|r", #open - 1) or ""
        w.status:SetText(d.dir == "owe" and ("|cffff8040you owe " .. C.Books.Name(d.who) .. " " .. left .. "|r" .. more)
          or ("|cffffd100" .. C.Books.Name(d.who) .. " owes you " .. left .. "|r" .. more))
      elseif r and #r.debts > 0 then w.status:SetText("|cff7CFC00split settled|r")
      else w.status:SetText("|cff7CFC00" .. tr[1].from .. " pays " .. tr[1].to .. " " .. C.Money(tr[1].amt) .. "|r") end
    elseif last and last.g and not last.settled and last.gview then w.status:SetText("|cffffd100split: waiting for the leader's numbers|r")
    else w.status:SetText("") end
    w.go:SetText("|cff7CFC00Start|r")
    showBest(nil)
  end
end

local function makeTile(parent, label, x, y, width)
  local t = CreateFrame("Frame", nil, parent)
  t:SetSize(width, 38); t:SetPoint("TOPLEFT", x, y)
  local bg = t:CreateTexture(nil, "BACKGROUND", nil, 1); bg:SetAllPoints(); bg:SetColorTexture(TILE[1], TILE[2], TILE[3], 0.9)
  local top = t:CreateTexture(nil, "BORDER"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
  top:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
  t.label = text(t, "GameFontDisableSmall", "CENTER"); t.label:SetPoint("TOP", 0, -3); t.label:SetText(label)
  t.value = text(t, "GameFontHighlight", "CENTER"); t.value:SetPoint("CENTER", 0, -1); t.value:SetWidth(width - 4)
  t.sub = text(t, "GameFontDisableSmall", "CENTER"); t.sub:SetPoint("BOTTOM", 0, 2); t.sub:SetWidth(width - 4)
  if t.sub.SetFont then local f, _, fl = t.sub:GetFont(); if f then t.sub:SetFont(f, 8, fl) end end
  -- one line each: a long text is cut short instead of wrapping over the value
  for _, fs in ipairs({ t.label, t.value, t.sub }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  return t
end

local function build()
  w = CreateFrame("Frame", "KinaWidget", UIParent)
  w:SetSize(W, H); w:SetFrameStrata("MEDIUM")
  C.RestorePos(w, "widget", "TOP", UIParent, "TOP", 0, -120)
  C.MakeDraggable(w, "widget")
  if C.ScaleGrip then C.ScaleGrip(w, "widgetScale") end
  w.bg = w:CreateTexture(nil, "BACKGROUND"); w.bg:SetAllPoints()
  local function edge(p1, p2, horiz, a)
    local t = w:CreateTexture(nil, "BORDER"); t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], a or 0.85)
    t:SetPoint(p1); t:SetPoint(p2)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
  end
  edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
  -- header band with a soft gradient
  local bar = w:CreateTexture(nil, "ARTWORK"); bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(22)
  bar:SetColorTexture(0.09, 0.15, 0.36, 0.95)
  if bar.SetGradient and CreateColor then pcall(bar.SetGradient, bar, "VERTICAL", CreateColor(0.05, 0.08, 0.20, 0.95), CreateColor(0.12, 0.20, 0.45, 0.95)) end
  local rule = w:CreateTexture(nil, "ARTWORK"); rule:SetPoint("TOPLEFT", 1, -23); rule:SetPoint("TOPRIGHT", -1, -23)
  rule:SetHeight(1); rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
  applyAlpha()

  local icon = w:CreateTexture(nil, "OVERLAY"); icon:SetSize(18, 18); icon:SetPoint("TOPLEFT", 4, -3)
  icon:SetTexture("Interface\\AddOns\\Kina\\Media\\KinaLogo")
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  title:SetText("KINA")
  -- mode chip
  w.chip = CreateFrame("Frame", nil, w); w.chip:SetSize(44, 14); w.chip:SetPoint("LEFT", title, "RIGHT", 6, 0)
  w.chip.bg = w.chip:CreateTexture(nil, "ARTWORK"); w.chip.bg:SetAllPoints()
  w.chip.text = text(w.chip, "GameFontHighlightSmall", "CENTER"); w.chip.text:SetPoint("CENTER", 0, 0)
  -- your Kina level (hover for details)
  w.rep = CreateFrame("Button", nil, w); w.rep:SetSize(70, 16); w.rep:SetPoint("LEFT", w.chip, "RIGHT", 6, 0)
  w.rep.text = text(w.rep, "GameFontHighlightSmall", "LEFT"); w.rep.text:SetPoint("LEFT", 0, 0)
  w.rep:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    if C.TipOwner then C.TipOwner(self) else GameTooltip:SetOwner(self, "ANCHOR_BOTTOM") end
    GameTooltip:AddLine("Kina level (experience)")
    for _, l in ipairs(C.RepDetail and C.RepDetail() or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  w.rep:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  local close = smallButton(w, "x", 20, function() C.ShowWidget(false) end); close:SetPoint("TOPRIGHT", -2, -2)
  tip(close, "Hide", "Hides the widget. /kina widget (or the minimap button) brings it back; a running farm keeps going.")
  local alpha = smallButton(w, "%", 22, function()
    local a = (C.settings.widgetAlpha or 0.85) + 0.15
    if a > 1.0 then a = 0.35 end
    C.settings.widgetAlpha = a; applyAlpha()
  end); alpha:SetPoint("RIGHT", close, "LEFT", -2, 0)
  tip(alpha, "Background", "Click to make the background more or less see-through.")
  w.snd = smallButton(w, "SND", 36, function()
    C.settings.farmSound = (C.settings.farmSound == false)
    if C.settings.farmSound then C.PlayCue("start") end
    C.RefreshWidget()
  end); w.snd:SetPoint("RIGHT", alpha, "LEFT", -2, 0)
  tip(w.snd, "Sound", "Turns the start and stop fanfares on or off.")

  -- hero: gold per hour
  w.rate = text(w, "GameFontNormalLarge", "LEFT"); w.rate:SetPoint("TOPLEFT", 10, -30); w.rate:SetWidth(180)
  if w.rate.SetFont then local f, _, fl = w.rate:GetFont(); if f then w.rate:SetFont(f, 20, fl or "OUTLINE") end end
  w.rateSub = text(w, "GameFontHighlightSmall", "LEFT"); w.rateSub:SetPoint("TOPLEFT", 10, -54); w.rateSub:SetWidth(190)
  w.clock = text(w, "GameFontNormalLarge", "RIGHT"); w.clock:SetPoint("TOPRIGHT", -10, -30); w.clock:SetWidth(100)
  w.timer = smallButton(w, "no timer", 74, function()
    local cur, nextP = C.settings.farmPreset or 0, 0
    for i, p in ipairs(PRESETS) do if p == cur then nextP = PRESETS[i % #PRESETS + 1] end end
    C.settings.farmPreset = nextP
    -- during a farm, a timer counts from NOW (1h = stop an hour from now); "no timer" removes it
    if C.session then C.session.limit = nextP > 0 and (C.SessionSecs(C.session) + nextP) or nil end
    C.RefreshWidget()
  end); w.timer:SetPoint("TOPRIGHT", -8, -50)
  tip(w.timer, "Timer", "Click to cycle a farm timer (1 to 4 hours). The farm stops itself when it runs out.")

  -- stat tiles
  local tw, gap, x0 = 68, 4, 8
  w.tNet = makeTile(w, "NET", x0, -72, tw)
  w.tCoin = makeTile(w, "COIN", x0 + (tw + gap), -72, tw)
  w.tLoot = makeTile(w, "LOOT", x0 + (tw + gap) * 2, -72, tw)
  w.tKills = makeTile(w, "KILLS", x0 + (tw + gap) * 3, -72, tw)

  -- best drop + status
  w.bestIcon = w:CreateTexture(nil, "OVERLAY"); w.bestIcon:SetSize(16, 16); w.bestIcon:SetPoint("TOPLEFT", 10, -116)
  w.best = text(w, "GameFontHighlightSmall", "LEFT"); w.best:SetPoint("LEFT", w.bestIcon, "RIGHT", 5, 0); w.best:SetWidth(W - 40)
  w.status = text(w, "GameFontHighlightSmall", "LEFT"); w.status:SetPoint("TOPLEFT", 10, -135); w.status:SetWidth(W - 20)
  for _, fs in ipairs({ w.rate, w.rateSub, w.clock, w.best, w.status }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end

  -- buttons
  w.go = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
  w.go:SetSize(96, 26); w.go:SetPoint("BOTTOMLEFT", 8, 8)
  w.go:SetScript("OnClick", function()
    if C.session then C.StopSession() else C.StartSession() end
  end)
  tip(w.go, "Start / Stop", "Start a farm here (your duo partner gets a Join popup). Stop ends it for everyone in the shared farm and works out the split.")
  w.pause = smallButton(w, "Pause", 60, function() if C.session then C.PauseSession() end; C.RefreshWidget() end, 26)
  w.pause:SetPoint("LEFT", w.go, "RIGHT", 4, 0)
  tip(w.pause, "Pause", "Stops the clock and leaves out anything looted until you resume (a trip to town, a break). Pauses your partner's widget too.")
  local runs = smallButton(w, "Log", 56, function() if C.OpenFarmLog then C.OpenFarmLog() else C.Toggle("Session") end end, 26)
  runs:SetPoint("LEFT", w.pause, "RIGHT", 4, 0)
  tip(runs, "Farm log", "Every kill, drop and coin this farm counted, newest first. Right-click a line to leave it out.")
  local hide = smallButton(w, "Kina", 64, function() C.Toggle() end, 26)
  hide:SetPoint("LEFT", runs, "RIGHT", 4, 0)
  tip(hide, "Kina", "Opens the main Kina window: dungeons, farms, Hot and skill-up plans.")
  -- pay what the split says you owe: opens the trade and puts the money in
  w.pay = smallButton(w, "Pay", W - 16, function()
    if w.pay.rcv then if C.RequestSettle then C.RequestSettle(w.pay.rcv) end
    elseif C.PayStart then C.PayStart(C.PayDue and C.PayDue()) end
  end, 20)
  w.pay:SetPoint("BOTTOMLEFT", 8, 38); w.pay:Hide()
  tip(w.pay, "Settle up", "Pay: opens a trade with your partner and puts in the exact amount the split says. Ask: sends them a Pay request. Stand close to each other.")

  local acc, tick = 0, 0
  w:SetScript("OnUpdate", function(_, el)
    -- big new best drop: the line glows for a moment
    if w.flash and w.flash > 0 then
      w.flash = w.flash - el
      local a = 0.5 + 0.5 * math.abs(math.sin((w.flash or 0) * 6))
      w.best:SetAlpha(a); w.bestIcon:SetAlpha(a)
      if w.flash <= 0 then w.best:SetAlpha(1); w.bestIcon:SetAlpha(1) end
    end
    acc = acc + el; if acc < 1 then return end
    tick = tick + acc; acc = 0
    if tick >= 5 then tick = 0; C.SessionTick() end
    C.RefreshWidget()
  end)
end

function C.ShowWidget(show)
  if show and not w then build() end
  C.settings.hudShown = show and true or false
  if w then if show then w:Show(); C.RefreshWidget() else w:Hide() end end
end
C.ShowHUD = C.ShowWidget

function C.ResetWidget()
  if w then C.RestorePos(w, "widget", "TOP", UIParent, "TOP", 0, -120) end
end

-- The idle/timer stop still works with the widget hidden.
local ticker = CreateFrame("Frame")
local tacc = 0
ticker:SetScript("OnUpdate", function(_, el)
  tacc = tacc + el
  if tacc < 5 or not C.ready then return end
  tacc = 0
  if not (w and w:IsShown()) then C.SessionTick() end
end)

C.OnSessionChange = function() C.RefreshWidget(); if C.Refresh then C.Refresh() end end
C.On("PLAYER_LOGIN", function() C.ShowWidget(C.settings.hudShown ~= false) end)
