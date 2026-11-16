-- Kina: hot mobs while you quest (1.0.5, Taylor: "entice the player to stop being led by
-- the nose and start tagging things that are profitable on their way through the game").
--  * a small line under the quest tracker when a hot mob is close: name, gold per kill,
--    distance and direction (click: waypoint; right-click: hide it for this zone)
--  * what your own last 20 kills were worth per kill, next to the hot mob's number
--  * hot mobs killed today and what they paid (the same per-kill values)
-- Quiet in combat, dungeons and raids, cities and inns, and on flight paths. Waypoints only
-- when you click; Kina never takes the arrow from a quest guide by itself.
local _, C = ...
local N = {}
C.HotNudge = N
N.NEAR_YD = 350       -- show a hot mob closer than this
N.SHOW_FOR = 120      -- seconds the line stays up for one mob before it waits for a new zone
N.RECENT = 20         -- your last N kills for the comparison

local GOLD, GREY, ORANGE = "|cffffc54a", "|cff9d9d9d", "|cffff7a1a"

local function db()
  C.db.hotNudge = type(C.db.hotNudge) == "table" and C.db.hotNudge or {}
  local d = C.db.hotNudge
  local today = date and date("%Y-%m-%d") or "?"
  if d.day ~= today then d.day, d.kills, d.gold = today, 0, 0 end
  d.recent = type(d.recent) == "table" and d.recent or {}
  return d
end
local function enabled() return not (C.settings and C.settings.hotNudgeOff) end

------------------------------------------------------------------ kills
-- every kill of yours (farm or not): its gold-per-kill value goes into "your last 20
-- kills", and a hot one into today's tally. Values are the hot list's own per-kill numbers,
-- so the two sides of the comparison are measured the same way.
function N.NoteKill(npc)
  local H = C.Hot
  if not (H and npc) then return end
  local r = H.Info(npc)
  local v = r and r.value
  if not v then return end
  local d = db()
  table.insert(d.recent, math.floor(v + 0.5))
  while #d.recent > N.RECENT do table.remove(d.recent, 1) end
  if r.tier then d.kills = (d.kills or 0) + 1; d.gold = (d.gold or 0) + v end
end
function N.RecentAverage()
  local d = db()
  if #d.recent < 5 then return nil end
  local s = 0
  for _, v in ipairs(d.recent) do s = s + v end
  return s / #d.recent, #d.recent
end
function N.Today()
  local d = db()
  return d.kills or 0, d.gold or 0
end
function N.TodayText()
  local k, g = N.Today()
  if k == 0 then return nil end
  return string.format("Hot mobs today: %d kill%s, %s", k, k == 1 and "" or "s", C.Money(math.floor(g + 0.5)))
end

------------------------------------------------------------------ where
local function yardsBetween(map, x1, y1, x2, y2)
  if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local ok, _, a = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x1, y1))
    local ok2, _, b = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x2, y2))
    if ok and ok2 and a and b and a.GetXY and b.GetXY then
      local ax, ay = a:GetXY(); local bx, by = b:GetXY()
      return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
    end
  end
  -- (no world positions: a zone is roughly 1000 yards across)
  return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 1000
end
local DIRS = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
local function direction(px, py, x, y)
  local a = math.atan2(-(y - py), x - px) -- map y grows southward
  local i = math.floor(((a / (2 * math.pi)) * 8 + 0.5)) % 8
  return DIRS[i + 1]
end

local function quiet()
  if InCombatLockdown and InCombatLockdown() then return true end
  if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
  if IsInInstance then local inI = IsInInstance(); if inI then return true end end
  if IsResting and IsResting() then return true end
  if UnitOnTaxi and UnitOnTaxi("player") then return true end
  return false
end

local seen = {}       -- [npc] = when its line first showed (this zone)
local hidden = {}     -- [npc] = true: right-clicked away (this zone)
local zoneKey
-- the nearest hot (or kill-on-sight) mob you could fight, or nil
function N.Nearest()
  local H = C.Hot
  if not H then return nil end
  local map, px, py = C.PlayerPos()
  if not (map and px) then return nil end
  local L = (UnitLevel and UnitLevel("player")) or 1
  local best, bd
  for _, r in ipairs(H.List()) do
    if r.tier and r.lvl >= L - 3 and r.lvl <= L + 3 and not hidden[r.npc] then
      local s = H.Spot(r.npc)
      if s and s.map == map and s.x then
        local d = yardsBetween(map, px, py, s.x, s.y)
        if d <= N.NEAR_YD and (not bd or d < bd) then best, bd = { row = r, spot = s, yd = d, dir = direction(px, py, s.x, s.y) }, d end
      end
    end
  end
  return best
end

------------------------------------------------------------------ the line
local f
local function build()
  if f then return f end
  f = CreateFrame("Button", "KinaHotNearby", UIParent)
  f:SetSize(260, 46); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.045, 0.03, 0.72)
  local edge = f:CreateTexture(nil, "BORDER"); edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(2); edge:SetColorTexture(1, 0.48, 0.1, 0.9)
  local logo = f:CreateTexture(nil, "ARTWORK"); logo:SetSize(22, 22); logo:SetPoint("LEFT", 6, 0)
  logo:SetTexture("Interface\\AddOns\\Kina\\Media\\KinaLogo")
  f.l1 = C.Text(f, "OVERLAY", "GameFontNormalSmall"); f.l1:SetPoint("TOPLEFT", 34, -5); f.l1:SetPoint("RIGHT", f, "RIGHT", -6, 0); f.l1:SetJustifyH("LEFT")
  f.l2 = C.Text(f, "OVERLAY", "GameFontHighlightSmall"); f.l2:SetPoint("TOPLEFT", f.l1, "BOTTOMLEFT", 0, -2); f.l2:SetPoint("RIGHT", f, "RIGHT", -6, 0); f.l2:SetJustifyH("LEFT")
  f.l3 = C.Text(f, "OVERLAY", "GameFontDisableSmall"); f.l3:SetPoint("TOPLEFT", f.l2, "BOTTOMLEFT", 0, -2); f.l3:SetPoint("RIGHT", f, "RIGHT", -6, 0); f.l3:SetJustifyH("LEFT")
  for _, fs in ipairs({ f.l1, f.l2, f.l3 }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.8, 0.4, 0.07)
  f:SetScript("OnClick", function(self, btn)
    local n = self.npc
    if not n then return end
    if btn == "RightButton" then hidden[n] = true; self:Hide(); return end
    if C.Hot then C.Hot.Waypoint(n) end
  end)
  f:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Hot mob nearby")
    GameTooltip:AddLine("Worth tagging on your way: it pays far more per kill than most mobs at this level.", 1, 1, 1, true)
    GameTooltip:AddLine("Click: waypoint to where it spawns thickest.  Right-click: hide it for this zone.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f:Hide()
  return f
end
local function anchor()
  f:ClearAllPoints()
  -- under the quest tracker when it's showing, else under the Kina widget, else the right side
  local tr = rawget(_G, "ObjectiveTrackerFrame") or rawget(_G, "QuestWatchFrame")
  local w = rawget(_G, "KinaWidget")
  if tr and tr.IsShown and tr:IsShown() and tr.GetBottom and tr:GetBottom() then f:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, -6)
  elseif w and w.IsShown and w:IsShown() then f:SetPoint("TOP", w, "BOTTOM", 0, -6)
  else f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 80) end
end

function N.Update()
  if not enabled() or quiet() then if f then f:Hide() end; return end
  local z = (GetRealZoneText and GetRealZoneText()) or "?"
  if z ~= zoneKey then zoneKey = z; seen, hidden = {}, {} end
  local n = N.Nearest()
  if not n then if f then f:Hide() end; return end
  local npc = n.row.npc
  local now = C.Now()
  seen[npc] = seen[npc] or now
  if now - seen[npc] > N.SHOW_FOR then if f then f:Hide() end; return end
  build(); anchor()
  f.npc = npc
  local tag = n.row.tier == "hot" and (ORANGE .. "Hot nearby|r") or (GOLD .. "Worth a kill nearby|r")
  f.l1:SetText(string.format("%s: |cffffffff%s|r", tag, n.row.name))
  f.l2:SetText(string.format("%s%s/kill|r  %s·  %d yd %s|r", GOLD, C.Money(math.floor(n.row.value + 0.5)), GREY, math.floor(n.yd / 5 + 0.5) * 5, n.dir))
  local avg = N.RecentAverage()
  local today = N.TodayText()
  f.l3:SetText(avg and string.format("Your last %d kills: %s each", #db().recent, C.Money(math.floor(avg + 0.5))) or (today or ""))
  f:SetHeight((f.l3:GetText() or "") ~= "" and 46 or 34)
  f:Show()
end

local tick = CreateFrame("Frame")
local acc = 0
tick:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 3 then return end
  acc = 0
  local ok, err = pcall(N.Update)
  if not ok and C.LogError then C.LogError("hot nearby", err) end
end)
C.On("PLAYER_REGEN_DISABLED", function() if f then f:Hide() end end)
