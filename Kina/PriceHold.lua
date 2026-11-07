local _, C = ...
-- 0.9.0 (Taylor): "every farm should end with a trip to the AH unless all Kina users in
-- the farm decline". When a group farm with debts ends, nobody owes anything yet: each
-- Kina user is asked to scan the auction house (or skip). When everyone has answered:
--  * if anyone scanned, the farm's leader re-prices the loot with its (now fresh) prices
--    and sends everyone the new incomes; every Kina works out the same split from them
--  * if everyone skipped, the split stands as it was
-- Then the debts start (and their clocks). A farm still waiting after 24 hours goes ahead
-- with the prices it has. Settings > Farming > "Ask for an AH scan when a farm ends".
local H = {}
C.PriceHold = H
local DAY = 86400
local function first(n) return n and (tostring(n):match("^([^%-]+)") or tostring(n)) or "" end
local function lower(n) return first(n):lower() end
local function myName() return first(UnitName and UnitName("player")) end
local function sidOf(s) return (s.sync and s.sync.sid) or ("t" .. tostring(s.start or 0)) end
-- the other Kina users in the farm (players without Kina can't answer, so they don't count)
local function members(s)
  local out, seen = {}, {}
  local pool = {}
  if s.sync and C.FarmSync and C.FarmSync.Totals then
    local ok, t = pcall(C.FarmSync.Totals, s.sync)
    if ok and t and t.members and next(t.members) then pool = t.members end
  end
  if not next(pool) then pool = s.split and s.split.incomes or {} end
  for who in pairs(pool) do
    local k = lower(who)
    if k ~= lower(myName()) and not seen[k] then seen[k] = true; out[#out + 1] = first(who) end
  end
  return out
end
local function sessionBySid(sid)
  for _, s in ipairs(C.db.sessions or {}) do if s.hold and sidOf(s) == sid then return s end end
end

------------------------------------------------------------------ the window
local win
local function window()
  if win then return win end
  win = CreateFrame("Frame", "KinaPriceHold", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(470, 250); win:SetPoint("CENTER", 0, 140); win:SetFrameStrata("FULLSCREEN_DIALOG"); win:SetToplevel(true)
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  if win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\AddOns\\Kina\\Media\\Cos\\bg_texture", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    win:SetBackdropBorderColor(0.85, 0.66, 0.30, 1)
  end
  win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); win.title:SetPoint("TOP", 0, -16)
  if C.Cos then C.Cos.Font(win.title, 22, "") end
  win.title:SetTextColor(1, 0.84, 0.43); win.title:SetText("Price the loot")
  local rule = win:CreateTexture(nil, "ARTWORK"); rule:SetPoint("TOPLEFT", 26, -46); rule:SetPoint("TOPRIGHT", -26, -46); rule:SetHeight(1); rule:SetColorTexture(0.47, 0.38, 0.20, 1)
  win.body = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); win.body:SetPoint("TOPLEFT", 26, -60); win.body:SetPoint("RIGHT", win, "RIGHT", -26, 0)
  win.body:SetJustifyH("LEFT"); win.body:SetJustifyV("TOP"); if win.body.SetSpacing then win.body:SetSpacing(3) end
  win.wait = win:CreateFontString(nil, "OVERLAY", "GameFontNormal"); win.wait:SetPoint("TOPLEFT", win.body, "BOTTOMLEFT", 0, -10); win.wait:SetPoint("RIGHT", win, "RIGHT", -26, 0)
  win.wait:SetJustifyH("LEFT")
  win.scan = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.scan:SetSize(120, 26); win.scan:SetPoint("BOTTOMRIGHT", -24, 18); win.scan:SetText("I'll scan")
  win.skip = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.skip:SetSize(190, 26); win.skip:SetPoint("RIGHT", win.scan, "LEFT", -10, 0); win.skip:SetText("Skip (use current prices)")
  if C.Skin then C.Skin.Button(win.scan); C.Skin.Button(win.skip) end
  return win
end
local function stateText(st)
  if st == "done" then return "|cff7CFC00scanned|r" elseif st == "skip" then return "|cff9d9d9dskipped|r" elseif st == "scan" then return "|cffffd100scanning|r" end
  return "|cffff9933waiting|r"
end
function H.ShowWindow(s)
  local w = window()
  w.s = s
  w.body:SetText("The farm is over. Before anyone owes anything, Kina prices the loot from a fresh auction house scan, "
    .. "so nobody's split uses old prices.\n\n|cffe8d6a0Visit an auction house and press Scan AH (about a minute).|r\n"
    .. "|cff9d9d9dIf every Kina user in the farm skips, the farm uses the prices it has now.|r")
  local function refresh()
    local h = s.hold or {}
    local parts = { myName() .. " " .. stateText(h.me) }
    for _, who in ipairs(members(s)) do parts[#parts + 1] = who .. " " .. stateText(h.peers and h.peers[lower(who)]) end
    w.wait:SetText("|cffffd100Kina users:|r  " .. table.concat(parts, "   "))
  end
  w.refresh = refresh
  w.scan:SetScript("OnClick", function() H.Answer(s, "scan"); w:Hide() end)
  w.skip:SetScript("OnClick", function() H.Answer(s, "skip"); w:Hide() end)
  refresh()
  w:SetHeight(math.max(230, (w.body:GetStringHeight() or 100) + 150))
  w:Show()
end

------------------------------------------------------------------ the hold
function H.Begin(s)
  if C.settings and C.settings.askScan == false then return end
  if s.noSplit or not (s.split and s.split.transfers and #s.split.transfers > 0) then return end
  s.hold = { at = C.Now(), me = "wait", peers = {}, leader = s.sync and s.sync.leader and first(s.sync.leader) or nil }
  if C.After then C.After(5, function() if s.hold and not s.hold.done then H.ShowWindow(s) end end) else H.ShowWindow(s) end
end
function H.Answer(s, what)
  local h = s.hold
  if not h or h.done then return end
  h.me = what
  if what == "skip" or what == "done" then
    if C.Share and C.Share.SendHold then C.Share.SendHold("prh", what == "done" and 1 or 2, sidOf(s), members(s)) end
    if what == "skip" then C.Print("you skipped the AH scan for this farm's prices.") end
  else
    C.Print("|cffffd100Kina will price this farm's loot from your next auction house scan.|r Open an auction house and press Scan AH.")
  end
  H.Check(s)
end
-- someone's answer, or the leader's re-priced incomes
function H.OnMessage(from, action, n, label)
  if action == "prh" then
    local s = sessionBySid(label or "")
    if not (s and s.hold) or s.hold.done then return end
    s.hold.peers[lower(from)] = (n == 1) and "done" or "skip"
    if win and win:IsShown() and win.s == s and win.refresh then win.refresh() end
    H.Check(s)
  elseif action == "prs" then
    local sid, list = (label or ""):match("^([^;]+);(.*)$")
    local s = sid and sessionBySid(sid)
    if not (s and s.hold) or s.hold.done then return end
    local by = {}
    for who, v in (list or ""):gmatch("([^=,]+)=(%-?%d+)") do by[who] = tonumber(v) end
    if next(by) then H.Apply(s, by) end
  end
end
-- new incomes -> the same split on every Kina
function H.Apply(s, by)
  if not (C.FarmSync and C.FarmSync.Split) then s.hold.done = true; return end
  local total, each, transfers = C.FarmSync.Split(by)
  s.split.total, s.split.each, s.split.incomes, s.split.transfers = total, each, by, transfers
  s.hold.done = true
  C.Print(string.format("|cffffd100Farm split re-priced|r (%s) from fresh auction prices:", s.label or "farm"))
  if #transfers == 0 then C.Print("   Everyone is even: nobody owes anything.") end
  for _, tr in ipairs(transfers) do C.Print(string.format("   |cff7CFC00%s pays %s %s|r", tr.from, tr.to, C.Money(tr.amt))) end
  if C.RefreshWidget then pcall(C.RefreshWidget) end
end
function H.Check(s)
  local h = s.hold
  if not h or h.done then return end
  if h.me == "wait" or h.me == "scan" then return end
  local anyScan = h.me == "done"
  for _, who in ipairs(members(s)) do
    local st = h.peers[lower(who)]
    if st ~= "done" and st ~= "skip" then return end
    if st == "done" then anyScan = true end
  end
  if not anyScan then
    h.done = true
    C.Print(string.format("everyone skipped the AH scan: the %s split stands as it was.", s.label or "farm"))
    return
  end
  -- the leader re-prices and tells everyone; the others wait for that
  if h.leader and lower(h.leader) == lower(myName()) and s.sync and C.FarmSync and C.FarmSync.Totals then
    local ok, t = pcall(C.FarmSync.Totals, s.sync, function(id, sfx) return C.SplitValue and (C.SplitValue(id, sfx)) or 0 end)
    if ok and t and t.byLooter then
      local by, parts = {}, {}
      for who, v in pairs(t.byLooter) do by[who] = math.floor(v + 0.5); parts[#parts + 1] = who .. "=" .. by[who] end
      table.sort(parts)
      if C.Share and C.Share.SendHold then C.Share.SendHold("prs", 0, sidOf(s) .. ";" .. table.concat(parts, ","), members(s)) end
      H.Apply(s, by)
      return
    end
  end
  h.ready = h.ready or C.Now()
end
-- every few seconds: did my scan finish? did the leader go quiet? is it 24 hours old?
local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, el)
  acc = acc + el; if acc < 5 then return end; acc = 0
  if not (C.db and C.db.sessions) then return end
  for i = 1, math.min(#C.db.sessions, 10) do
    local s = C.db.sessions[i]
    local h = s.hold
    if h and not h.done then
      if h.me == "scan" and C.market and C.market.scanTime and s.stop and C.market.scanTime > s.stop then
        h.me = "done"
        if C.Share and C.Share.SendHold then C.Share.SendHold("prh", 1, sidOf(s), members(s)) end
        C.Print("|cff7CFC00scan done:|r this farm's loot will be priced from it.")
        H.Check(s)
      elseif h.me == "wait" and C.market and C.market.scanTime and s.stop and C.market.scanTime > s.stop then
        -- scanned without answering the window: that counts as scanning
        H.Answer(s, "done")
      end
      if h.ready and C.Now() - h.ready > 600 then
        h.done = true; C.Print("the farm leader didn't send new prices: the split stands as it was.")
      elseif C.Now() - (h.at or 0) > DAY then
        h.done = true; C.Print(string.format("the %s farm waited a day for AH scans: its split goes ahead as it was.", s.label or "farm"))
      end
    end
  end
end)
