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
local function ironOn() return C.Skin and C.Skin.On() end
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
  -- 1.1.1: Kina's own font copies, so the widget follows the Text size setting (115% by default)
  local fs = C.Text and C.Text(parent, "OVERLAY", font or "GameFontHighlightSmall") or parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end
local function tip(btn, title, body) if C.ButtonTip then C.ButtonTip(btn, title, body) end end
local function smallButton(parent, label, width, onClick, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height or 18); b:SetText(label); b:SetScript("OnClick", onClick)
  if b.GetFontString and b:GetFontString() then b:GetFontString():SetFontObject(C.Font and C.Font("GameFontHighlightSmall") or "GameFontHighlightSmall") end
  if C.Skin then C.Skin.Button(b) end
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
    local cnt, val, who = {}, {}, {}
    for _, ev in ipairs(s.sync.chain) do
      if ev.kind == "L" and not ex[ev.seq] then
        local id, n, _, v = (ev.data or ""):match("^(%d*):(%d*):([^:]*):(%-?%d*)$")
        id, n, v = tonumber(id), tonumber(n) or 1, tonumber(v) or 0
        if id then
          cnt[id] = (cnt[id] or 0) + n; val[id] = (val[id] or 0) + n * v
          who[id] = who[id] or {}; who[id][ev.origin or "?"] = true
        end
      end
    end
    for id, v in pairs(val) do if v > bestV then bestID, bestV, bestN = id, v, cnt[id] end end
    -- 1.2.6: whose drop it was (not whose Kina priced it)
    local names, k = {}, 0
    for nm in pairs(bestID and who[bestID] or {}) do k = k + 1; names[#names + 1] = C.Books.Name(nm) end
    return bestID, bestV, bestN, (k == 1 and names[1]) or (k > 1 and "the group") or nil
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
  local c = (C.Skin and C.Skin.On()) and { 0.055, 0.055, 0.06 } or BG -- iron look: neutral near-black, no navy
  if w and w.bg then w.bg:SetColorTexture(c[1], c[2], c[3], C.settings.widgetAlpha or 0.85) end
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
  local id, v, n, looter = nil, 0, 0, nil
  if s then id, v, n, looter = bestDrop(s) end
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

-- (plain locals, not fields on the frame: 1.2.2)
local chipIron, modeWord = false, nil
-- the line under gold per hour; in the iron look it carries the mode ("per hour · duo · Darkshore")
local function setSub(txt)
  if chipIron then
    txt = txt:gsub("^per hour, group", "per hour")
    if modeWord then
      local head, rest = txt:match("^(%S+ %S+)%s+(.*)$")
      if head then txt = head .. "  |cff6f6f6f·|r  " .. modeWord .. "  |cff6f6f6f·|r  " .. rest
      else txt = txt .. "  |cff6f6f6f·|r  " .. modeWord end
    end
  end
  w.rateSub:SetText(txt)
end
local function chip(textv, r, g, b)
  w.chip.text:SetText(textv)
  if chipIron then
    -- 1.2.2: no badge in the header; the mode goes into the line under the gold
    local function up(v) return math.floor(math.min(1, 0.35 + v * 1.6) * 255) end
    modeWord = (textv ~= "READY") and string.format("|cff%02x%02x%02x%s|r", up(r), up(g), up(b), textv:lower()) or nil
    return
  end
  w.chip.bg:SetColorTexture(r, g, b, 0.9)
  w.chip:SetWidth(math.max(40, (w.chip.text:GetStringWidth() or 30) + 12))
end

-- 1.5.3 (Taylor): your party under the widget: each member's portrait in their standing
-- ring (their Kina level on the plate, a mentor star when they have one); click one for
-- their Kina profile. Hidden when you're alone.
local strip
local function first(n) return n and (tostring(n):match("^([^%-]+)") or tostring(n)) or "" end
local function partyStrip()
  if not (C.Cos and C.Cos.Portrait) then return end
  local mates = {}
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local raid = IsInRaid and IsInRaid()
  local me = UnitName and UnitName("player")
  for i = 1, n do
    local u = raid and ("raid" .. i) or ("party" .. i)
    local ok, un = pcall(UnitName, u)
    if ok and un and not (issecretvalue and issecretvalue(un)) and un ~= me and #mates < 4 then mates[#mates + 1] = { u = u, name = first(un) } end
  end
  if #mates == 0 then if strip then strip:Hide() end; return end
  if not strip then
    strip = CreateFrame("Frame", nil, w)
    strip:SetHeight(78)
    if C.Skin and C.Skin.On() and C.Skin.Panel then C.Skin.Panel(strip, 6)
    else local bg = strip:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6) end
    strip.cells = {}
    for i = 1, 4 do
      local c = CreateFrame("Button", nil, strip); c:SetSize(70, 70)
      c.box = CreateFrame("Frame", nil, c); c.box:SetSize(38, 38); c.box:SetPoint("TOP", 0, -10)
      c.portrait = c.box:CreateTexture(nil, "ARTWORK")
      c.cos = C.Cos.Portrait(c.box, c.portrait)
      c.cos.plate:SetSize(22, 22); C.Cos.Font(c.cos.num, 9, "OUTLINE")
      c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.name:SetPoint("BOTTOM", 0, 0); c.name:SetWidth(70)
      if c.name.SetWordWrap then c.name:SetWordWrap(false) end
      local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.4, 0.08)
      c:SetScript("OnClick", function(self) if self.who and C.Profile then C.Profile.Show(self.who) end end)
      c:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.who) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(self.who); GameTooltip:AddLine("Click for their Kina profile", 1, 1, 1); GameTooltip:Show()
      end)
      c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      strip.cells[i] = c
    end
  end
  strip:ClearAllPoints(); strip:SetPoint("TOPLEFT", w, "BOTTOMLEFT", 0, -4); strip:SetPoint("TOPRIGHT", w, "BOTTOMRIGHT", 0, -4)
  local cw = (w:GetWidth() or 324) / 4
  for i, c in ipairs(strip.cells) do
    local m = mates[i]
    if m then
      c:ClearAllPoints(); c:SetPoint("TOP", strip, "TOPLEFT", cw * (i - 0.5) + (4 - #mates) * cw / 2, -4)
      c.who = m.name
      if c.lastUnit ~= m.u .. m.name and SetPortraitTexture then pcall(SetPortraitTexture, c.portrait, m.u); c.lastUnit = m.u .. m.name end
      local pr = C.Share and C.Share.ProfileOf and C.Share.ProfileOf(m.name)
      local stand = pr and pr.stand
      local sname = type(stand) == "number" and C.Rep and C.Rep.StandingOf(stand) or nil
      local klv = pr and pr.kinaLv
      C.Cos.UpdatePortrait(c.cos, sname or "Unproven", (klv and klv > 0) and klv or 1)
      if klv and klv > 0 then c.cos.plate:Show(); c.cos.num:Show() else c.cos.plate:Hide(); c.cos.num:Hide() end
      c.name:SetText((pr and "|cffffffff" or "|cff9d9d9d") .. m.name .. "|r")
      c:Show()
    else c:Hide(); c.who = nil end
  end
  strip:Show()
end

function C.RefreshWidget()
  if not (w and w:IsShown()) then return end
  pcall(refreshPay)
  pcall(partyStrip)
  -- 1.1.0: the Scan AH button and what it's doing
  if w.scan then
    if C.ahOpen and not w.pay:IsShown() then
      local sc = C.scan or {}
      local left = C.ScanCooldown and C.ScanCooldown() or 0
      local txt
      if sc.phase == "request" then txt = "Scan AH: asking the auction house..."
      elseif sc.phase == "read" or sc.phase == "items" then txt = string.format("Scan AH: reading %d%%", math.floor(100 * (sc.done or 0) / math.max(1, sc.total or 1)))
      elseif sc.phase == "done" then txt = string.format("|cff7CFC00Scan done: %d listings|r", sc.rows or 0)
      elseif left > 0 then txt = string.format("%s  |cff9d9d9d(next in %d:%02d)|r", C.scanLoop and "Auto-scanning" or "Scan AH", math.floor(left / 60), left % 60)
      else txt = C.scanLoop and "Auto-scanning: scanning now" or "Scan AH" end
      w.scan:SetText(txt); w.scan:Show()
    else w.scan:Hide() end
  end
  local s = C.session
  if w.sndIcon then w.sndIcon:SetTexture(C.Cos.Tex(C.settings.farmSound == false and "sound_off" or "sound_on"))
  elseif chipIron then w.snd:SetText(C.settings.farmSound == false and "|cff888888Muted|r" or "Sound")
  else w.snd:SetText(C.settings.farmSound == false and "|cff888888SND|r" or "SND") end
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
        setSub("per hour, group" .. (v.noSplit and " |cffffd100no split|r" or "") .. "  |cff9d9d9d" .. ((s.label or "farm"):sub(1, v.noSplit and 10 or 16)) .. "|r")
        setTile(w.tNet, signed(v.net), "same for all")
        setTile(w.tCoin, C.Money(v.coin or 0), "game split")
        setTile(w.tLoot, C.Money(v.items or 0), ((v.used or 0) > 0) and ("used " .. C.Money(v.used)) or "split prices")
        -- 1.4.6: the kills tile's second line is game XP per hour (falls back to kills/h)
        local xph = C.GameXPPerHour and C.GameXPPerHour(s)
        setTile(w.tKills, tostring(v.kills or 0), xph and C.FmtXPH(xph) or (secs >= 60 and string.format("%d / hour", (v.kills or 0) * 3600 / secs) or ""))
        if s.sync then
          local bw = select(4, bestDrop(s))
          w.status:SetText(bw and ("|cff9d9d9dbest drop: " .. (bw == "the group" and "the group's" or (bw .. "'s")) .. "|r") or "|cff9d9d9dshared with the group|r")
        -- 1.0.10: the farm started before Kina saw your partner's Kina: it isn't shared, and
        -- their loot only counts when they loot near you
        else w.status:SetText("|cffff8040not shared: Stop, then Start again to share|r") end
      else
        chip("WAITING", 0.45, 0.35, 0.05)
        w.clock:SetText("|cff9d9d9d" .. clock(C.SessionSecs(s)) .. "|r")
        w.rate:SetText("|cff9d9d9d...|r"); setSub("waiting for " .. tostring(leader) .. "'s numbers")
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
    setSub("per hour  |cff9d9d9d" .. ((s.label or "farm"):sub(1, 20)) .. "|r")
    setTile(w.tNet, signed(sum.total), ((sum.used or 0) > 0) and ("used " .. C.Money(sum.used)) or "what you looted")
    setTile(w.tCoin, C.Money(sum.cash or 0), ((s.money.pickpocket or 0) > 0) and ("picks " .. C.Money(s.money.pickpocket)) or "looted coin")
    local extra = {}
    if (s.skins or 0) > 0 then extra[#extra + 1] = s.skins .. " skins" end
    if (s.nodes or 0) > 0 then extra[#extra + 1] = s.nodes .. " nodes" end
    setTile(w.tLoot, C.Money(sum.items or 0), table.concat(extra, ", "))
    local xph = C.GameXPPerHour and C.GameXPPerHour(s)
    setTile(w.tKills, tostring(sum.kills or 0), xph and C.FmtXPH(xph) or (secs >= 60 and string.format("%d / hour", (sum.kills or 0) * 3600 / secs) or ""))
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
      setSub("last farm  |cff9d9d9d" .. ((last.label or "?"):sub(1, 18)) .. ", " .. (last.why or "stopped") .. "|r")
      setTile(w.tNet, signed(net), last.gview and "group" or "")
      setTile(w.tCoin, C.Money((last.gview and last.gview.coin) or (last.result and last.result.cash) or 0), "")
      setTile(w.tLoot, C.Money((last.gview and last.gview.items) or (last.result and last.result.items) or 0), "")
      setTile(w.tKills, tostring(g.kills or 0), "")
    else
      w.rate:SetText("|cff9d9d9d--|r"); modeWord = nil; setSub("press Start when you begin farming")
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
      local tot = C.PayDue and C.PayDue()
      if not tot then tot = C.ReceiveDue and C.ReceiveDue(); if tot then tot.to = tot.from end end
      if tot and tot.n and tot.n > 1 then
        -- 1.2.6: the total with that person across every open farm, same as the button
        local nm = C.Books.Name(tot.to)
        local farms = string.format(" |cff9d9d9d(%d farms)|r", tot.n)
        w.status:SetText(C.PayDue() and ("|cffff8040you owe " .. nm .. " " .. C.Money(tot.amt) .. "|r" .. farms)
          or ("|cffffd100" .. nm .. " owes you " .. C.Money(tot.amt) .. "|r" .. farms))
      elseif d then
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
  t:SetSize(width, (C.Skin and C.Skin.On()) and 44 or 38); t:SetPoint("TOPLEFT", x, y)
  local bg = t:CreateTexture(nil, "BACKGROUND", nil, 1); bg:SetAllPoints(); bg:SetColorTexture(TILE[1], TILE[2], TILE[3], 0.9)
  local top = t:CreateTexture(nil, "BORDER"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
  top:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
  -- 1.1.0 iron look: the recessed tray, text pulled in clear of its 5 px border
  local iron = C.Skin and C.Skin.On()
  if iron then bg:Hide(); top:Hide(); C.Skin.Tile(t, 5) end
  t.label = text(t, "GameFontDisableSmall", "CENTER"); t.label:SetPoint("TOP", 0, iron and -5 or -3); t.label:SetText(label)
  t.value = text(t, "GameFontHighlight", "CENTER"); t.value:SetPoint("CENTER", 0, -1); t.value:SetWidth(width - (iron and 10 or 4))
  t.sub = text(t, "GameFontDisableSmall", "CENTER"); t.sub:SetPoint("BOTTOM", 0, iron and 5 or 2); t.sub:SetWidth(width - (iron and 10 or 4))
  if t.sub.SetFont then local f, _, fl = t.sub:GetFont(); if f then t.sub:SetFont(f, 8 * (C.TextScale and C.TextScale() or 1), fl) end end
  -- one line each: a long text is cut short instead of wrapping over the value
  for _, fs in ipairs({ t.label, t.value, t.sub }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  return t
end

local function build()
  local ironLook = C.Skin and C.Skin.On()
  if ironLook then W = 324 end -- 1.2.0: wider, so the 115% text fits the tiles
  w = CreateFrame("Frame", "KinaWidget", UIParent)
  local DY = ironLook and 8 or 0 -- 1.1.1: taller tiles in the iron look
  w:SetSize(W, H + DY); w:SetFrameStrata("MEDIUM")
  C.RestorePos(w, "widget", "TOP", UIParent, "TOP", 0, -120)
  if C.Cos and C.Cos.Glow then pcall(C.Cos.Glow, w, 10) end -- 1.5.0: standing glow on the widget
  -- 1.1.1: with the iron look the widget moves by its title area only
  local handle
  if ironLook then
    handle = CreateFrame("Frame", nil, w)
    handle:SetPoint("TOPLEFT", 0, 0); handle:SetSize(206, 26)
    handle:SetFrameLevel(w:GetFrameLevel() + 1)
  end
  C.MakeDraggable(w, "widget", handle)
  if C.ScaleGrip then C.ScaleGrip(w, "widgetScale") end
  w.bg = w:CreateTexture(nil, "BACKGROUND"); w.bg:SetAllPoints()
  local iron = C.Skin and C.Skin.On()
  local function edge(p1, p2, horiz, a)
    if iron then return end
    local t = w:CreateTexture(nil, "BORDER"); t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], a or 0.85)
    t:SetPoint(p1); t:SetPoint(p2)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
  end
  edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
  -- 1.1.0 iron look: the A-30 frame (20 px, Rev 59) and the A-33 header bar
  if iron then
    C.Skin.Frame(w, 20, false)
    -- 1.2.2: a plain header (the hammered strip behind small text was unreadable),
    -- just a fine gold rule under it
    local rl = w:CreateTexture(nil, "ARTWORK"); rl:SetPoint("TOPLEFT", 10, -27); rl:SetPoint("TOPRIGHT", -10, -27)
    rl:SetHeight(1); rl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
  end
  -- header band with a soft gradient
  local bar = w:CreateTexture(nil, "ARTWORK"); bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(22)
  bar:SetColorTexture(0.09, 0.15, 0.36, 0.95)
  if bar.SetGradient and CreateColor then pcall(bar.SetGradient, bar, "VERTICAL", CreateColor(0.05, 0.08, 0.20, 0.95), CreateColor(0.12, 0.20, 0.45, 0.95)) end
  local rule = w:CreateTexture(nil, "ARTWORK"); rule:SetPoint("TOPLEFT", 1, -23); rule:SetPoint("TOPRIGHT", -1, -23)
  rule:SetHeight(1); rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
  if iron then bar:Hide(); rule:Hide() end
  applyAlpha()

  local icon = w:CreateTexture(nil, "OVERLAY"); icon:SetSize(18, 18); icon:SetPoint("TOPLEFT", 4, -3)
  icon:SetTexture("Interface\\AddOns\\Kina\\Media\\KinaLogo")
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  title:SetText("KINA")
  -- mode chip
  w.chip = CreateFrame("Frame", nil, w); w.chip:SetSize(44, iron and 18 or 14); w.chip:SetPoint("LEFT", title, "RIGHT", 6, 0)
  w.chip.bg = w.chip:CreateTexture(nil, "ARTWORK"); w.chip.bg:SetAllPoints()
  w.chip.text = text(w.chip, "GameFontHighlightSmall", "CENTER"); w.chip.text:SetPoint("CENTER", 0, 0)
  if iron then w.chip.bg:Hide(); chipIron = true end
  -- your Kina level (hover for details)
  w.rep = CreateFrame("Button", nil, w); w.rep:SetSize(70, 16); w.rep:SetPoint("LEFT", w.chip, "RIGHT", 6, 0)
  w.rep:SetFrameLevel(w:GetFrameLevel() + 5)
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
    if C.settings.farmSound then C.PlayClick() end
    C.RefreshWidget()
  end); w.snd:SetPoint("RIGHT", alpha, "LEFT", -2, 0)
  tip(w.snd, "Sound", "Turns the start and stop fanfares on or off.")

  -- hero: gold per hour
  w.rate = text(w, "GameFontNormalLarge", "LEFT"); w.rate:SetPoint("TOPLEFT", 10, -30); w.rate:SetWidth(180)
  if w.rate.SetFont then local f, _, fl = w.rate:GetFont(); if f then w.rate:SetFont(f, 20 * (C.TextScale and C.TextScale() or 1), fl or "OUTLINE") end end
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
  local tw, gap, x0 = ironLook and 74 or 68, 4, 8
  w.tNet = makeTile(w, "NET", x0, -72, tw)
  w.tCoin = makeTile(w, "COIN", x0 + (tw + gap), -72, tw)
  w.tLoot = makeTile(w, "LOOT", x0 + (tw + gap) * 2, -72, tw)
  w.tKills = makeTile(w, "KILLS", x0 + (tw + gap) * 3, -72, tw)

  -- best drop + status
  w.bestIcon = w:CreateTexture(nil, "OVERLAY"); w.bestIcon:SetSize(16, 16); w.bestIcon:SetPoint("TOPLEFT", 10, -116 - DY)
  w.best = text(w, "GameFontHighlightSmall", "LEFT"); w.best:SetPoint("LEFT", w.bestIcon, "RIGHT", 5, 0); w.best:SetWidth(W - 40)
  w.status = text(w, "GameFontHighlightSmall", "LEFT"); w.status:SetPoint("TOPLEFT", 10, -135 - DY); w.status:SetWidth(W - 20)
  for _, fs in ipairs({ w.rate, w.rateSub, w.clock, w.best, w.status }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end

  -- buttons
  w.go = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
  w.go:SetSize(ironLook and 100 or 96, 26); w.go:SetPoint("BOTTOMLEFT", 8, 8)
  if C.Skin then C.Skin.Button(w.go) end
  w.go:SetScript("OnClick", function()
    if C.session then C.StopSession() else C.StartSession() end
  end)
  tip(w.go, "Start / Stop", "Start a farm here (your duo partner gets a Join popup). Stop ends it for everyone in the shared farm and works out the split.")
  w.pause = smallButton(w, "Pause", ironLook and 64 or 60, function() if C.session then C.PauseSession() end; C.RefreshWidget() end, 26)
  w.pause:SetPoint("LEFT", w.go, "RIGHT", 4, 0)
  tip(w.pause, "Pause", "Stops the clock and leaves out anything looted until you resume (a trip to town, a break). Pauses your partner's widget too.")
  local runs = smallButton(w, "Log", ironLook and 60 or 56, function() if C.OpenFarmLog then C.OpenFarmLog() else C.Toggle("Session") end end, 26)
  runs:SetPoint("LEFT", w.pause, "RIGHT", 4, 0)
  tip(runs, "Farm log", "Every kill, drop and coin this farm counted, newest first. Right-click a line to leave it out.")
  local hide = smallButton(w, "Kina", ironLook and 68 or 64, function() C.Toggle() end, 26)
  hide:SetPoint("LEFT", runs, "RIGHT", 4, 0)
  tip(hide, "Kina", "Opens the main Kina window: dungeons, farms, Hot and skill-up plans.")
  -- pay what the split says you owe: opens the trade and puts the money in
  w.pay = smallButton(w, "Pay", W - 16, function(_, btn)
    -- 1.1.1: right-click opens the farm's Ledger details (forgive, more time)
    if btn == "RightButton" then
      local due = w.pay.rcv or (C.PayDue and C.PayDue())
      if due and due.s and C.OpenLedgerFarm then C.OpenLedgerFarm(due.s) end
      return
    end
    if w.pay.rcv then if C.RequestSettle then C.RequestSettle(w.pay.rcv) end
    elseif C.PayStart then C.PayStart(C.PayDue and C.PayDue()) end
  end, (C.Skin and C.Skin.On()) and 24 or 20)
  w.pay:SetPoint("BOTTOMLEFT", 8, 38); w.pay:Hide()
  -- 1.1.0: at the auction house the same spot is a Scan AH button (when nothing is owed)
  w.scan = smallButton(w, "Scan AH", W - 16, function() if C.StartScanLoop then C.StartScanLoop() end; C.RefreshWidget() end,
    (C.Skin and C.Skin.On()) and 24 or 20)
  w.scan:SetPoint("BOTTOMLEFT", 8, 38); w.scan:Hide()
  w.scan:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    if C.TipOwner then C.TipOwner(self) else GameTooltip:SetOwner(self, "ANCHOR_BOTTOM") end
    GameTooltip:AddLine("Auction house scan", 1, 0.82, 0)
    GameTooltip:AddLine("Kina prices your loot from auction scans: yours, or a groupmate's shared scan, whichever is newest.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(C.ScanSourceText and C.ScanSourceText() or "no scan yet", 0.31, 0.76, 0.97, true)
    GameTooltip:AddLine("Click to scan now; Kina then rescans every 15 minutes (the game's limit) while the auction house is open.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  w.scan:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  w.pay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  tip(w.pay, "Settle up", "Pay: opens a trade with your partner and puts in the exact amount the split says. Ask: sends them a Pay request. Stand close to each other.\n\nRight-click: the Debts page (Pay, more time, Forgive).")

  -- 1.2.1 iron look: a clean layout with fixed, chosen text sizes. Scaling the game's
  -- small fonts up made text sit on the tile borders and crowd the header; the whole
  -- widget can still be made bigger with its corner grip.
  if ironLook then
    local FONT = STANDARD_TEXT_FONT or (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"
    local function fx(fs, size, justify)
      if not (fs and fs.SetFont) then return end
      fs:SetFont(FONT, size, "")
      if fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) end
      if justify then fs:SetJustifyH(justify) end
    end
    local function place(f, point, x, y) f:ClearAllPoints(); f:SetPoint(point, w, point, x, y) end
    local IH = 256
    w:SetSize(W, IH)
    -- header: logo, KINA, mode, level ... Sound, close
    icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", 10, -5); icon:SetSize(18, 18)
    fx(title, 14); title:SetText("Kina"); title:SetTextColor(1, 0.82, 0.25)
    title:ClearAllPoints(); title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    w.chip.text:Hide()
    -- your Kina level: hover the logo (it's also on the You tab)
    w.rep:ClearAllPoints(); w.rep:SetPoint("TOPLEFT", w, "TOPLEFT", 8, -3); w.rep:SetSize(70, 22)
    w.rep.text:Hide()
    alpha:Hide() -- (background: Settings, or right-click the title)
    close:Hide()
    local x = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    x:SetSize(24, 24); x:SetPoint("TOPRIGHT", w, "TOPRIGHT", 1, 1); x:SetFrameLevel(w:GetFrameLevel() + 40)
    x:SetScript("OnClick", function() C.ShowWidget(false) end)
    tip(x, "Hide", "Hides the widget. /kina widget (or the minimap button) brings it back; a running farm keeps going.")
    -- 1.5.3 (Taylor): the same KINA nameplate as the main window, centred on the top edge;
    -- the sound toggle is a speaker in the top-left corner, opposite the close X
    icon:Hide(); title:Hide()
    local plate = CreateFrame("Frame", nil, w); plate:SetSize(190, 48); plate:SetPoint("CENTER", w, "TOP", 0, 2)
    plate:SetFrameLevel(w:GetFrameLevel() + 45)
    local pt = plate:CreateTexture(nil, "BACKGROUND"); pt:SetAllPoints(); pt:SetTexture(C.Cos and C.Cos.Tex("kina_plaque") or nil)
    local pc = plate:CreateTexture(nil, "OVERLAY"); pc:SetSize(30, 30); pc:SetPoint("CENTER", plate, "CENTER", -50, 0)
    pc:SetTexture("Interface\\AddOns\\Kina\\Media\\KinaLogo")
    local pw = plate:CreateTexture(nil, "ARTWORK"); pw:SetSize(100, 25); pw:SetPoint("CENTER", plate, "CENTER", 11, 0)
    pw:SetTexture(C.Cos and C.Cos.Tex("kina_word") or nil)
    if C.DragBy then C.DragBy(w, plate) end
    -- hovering the plate shows your Kina level (what the little level button did)
    plate:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      if C.TipOwner then C.TipOwner(self) else GameTooltip:SetOwner(self, "ANCHOR_BOTTOM") end
      GameTooltip:AddLine("Kina level (experience)")
      for _, l in ipairs(C.RepDetail and C.RepDetail() or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    plate:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    w.rep:Hide()
    w.snd:SetSize(24, 22); w.snd:ClearAllPoints(); w.snd:SetPoint("TOPLEFT", w, "TOPLEFT", 6, -2)
    w.snd:SetFrameLevel(w:GetFrameLevel() + 40)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do local t = w.snd[k]; if t and t.Hide then t:Hide() end end
    if w.snd.GetNormalTexture and w.snd:GetNormalTexture() then w.snd:GetNormalTexture():SetAlpha(0) end
    if w.snd.GetPushedTexture and w.snd:GetPushedTexture() then w.snd:GetPushedTexture():SetAlpha(0) end
    w.sndIcon = w.snd:CreateTexture(nil, "OVERLAY"); w.sndIcon:SetSize(20, 20); w.sndIcon:SetPoint("CENTER")
    if w.snd:GetFontString() then w.snd:GetFontString():Hide() end
    if handle then
      handle:EnableMouse(true)
      handle:HookScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then
          local a = (C.settings.widgetAlpha or 0.85) + 0.15
          if a > 1.0 then a = 0.35 end
          C.settings.widgetAlpha = a; applyAlpha()
        end
      end)
    end
    -- hero row: gold per hour on the left, the clock and timer on the right
    place(w.rate, "TOPLEFT", 14, -34); fx(w.rate, 24); w.rate:SetWidth(190)
    place(w.rateSub, "TOPLEFT", 15, -62); fx(w.rateSub, 11); w.rateSub:SetWidth(200)
    place(w.clock, "TOPRIGHT", -14, -35); fx(w.clock, 19, "RIGHT"); w.clock:SetWidth(110)
    w.timer:ClearAllPoints(); w.timer:SetPoint("TOPRIGHT", w, "TOPRIGHT", -12, -58); w.timer:SetSize(86, 20)
    if w.timer:GetFontString() then fx(w.timer:GetFontString(), 10) end
    -- tiles: 74 x 54, label / value / note each clear of the 5 px border
    local tw, gap, x0, ty = 74, 4, 10, -86
    for i, tl in ipairs({ w.tNet, w.tCoin, w.tLoot, w.tKills }) do
      tl:ClearAllPoints(); tl:SetPoint("TOPLEFT", w, "TOPLEFT", x0 + (i - 1) * (tw + gap), ty); tl:SetSize(tw, 54)
      fx(tl.label, 9, "CENTER"); tl.label:ClearAllPoints(); tl.label:SetPoint("TOP", tl, "TOP", 0, -9)
      tl.label:SetTextColor(0.62, 0.62, 0.62)
      fx(tl.value, 13, "CENTER"); tl.value:ClearAllPoints(); tl.value:SetPoint("CENTER", tl, "CENTER", 0, -1); tl.value:SetWidth(tw - 6)
      fx(tl.sub, 8, "CENTER"); tl.sub:ClearAllPoints(); tl.sub:SetPoint("BOTTOM", tl, "BOTTOM", 0, 9); tl.sub:SetWidth(tw - 12)
      tl.sub:SetTextColor(0.55, 0.55, 0.55)
    end
    -- best drop and status
    w.bestIcon:ClearAllPoints(); w.bestIcon:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -150); w.bestIcon:SetSize(18, 18)
    fx(w.best, 11); w.best:SetWidth(W - 50)
    place(w.status, "TOPLEFT", 15, -174); fx(w.status, 11); w.status:SetWidth(W - 30)
    -- buttons
    for _, b in ipairs({ w.go, w.pause, runs, hide, w.pay, w.scan }) do
      if b and b.GetFontString and b:GetFontString() then fx(b:GetFontString(), 12) end
    end
    w.pay:ClearAllPoints(); w.pay:SetPoint("BOTTOMLEFT", 10, 40); w.pay:SetWidth(W - 20)
    w.scan:ClearAllPoints(); w.scan:SetPoint("BOTTOMLEFT", 10, 40); w.scan:SetWidth(W - 20)
    w.go:ClearAllPoints(); w.go:SetPoint("BOTTOMLEFT", 10, 10)
    local bw = math.floor((W - 20 - 3 * 4) / 4)
    for _, b in ipairs({ w.go, w.pause, runs, hide }) do b:SetSize(bw, 26) end
  end

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
    -- 1.2.4: name the step, so a blocked call says which part of Kina was running
    if tick >= 5 then tick = 0; C.stage = "session tick"; C.SessionTick() end
    C.stage = "widget refresh"; C.RefreshWidget(); C.stage = "running"
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
