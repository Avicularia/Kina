-- Kina: pickpocket spots on the world map.
-- Bubbles where you (and players who shared with you) picked pockets; nearby spots
-- merge. Colour = how well the spot pays per pick at today's prices, compared with
-- the rest of the map: gold = best third, silver = middle, copper = lowest.
local _, C = ...
local P = C.Pockets
local TEMPLATE = "KinaPocketPinTemplate"
local RADIUS = 0.035
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local TIERS = {
  { name = "Rich pickings", r = 1.00, g = 0.82, b = 0.10 },
  { name = "Decent pockets", r = 0.80, g = 0.82, b = 0.90 },
  { name = "Slim pickings", r = 0.85, g = 0.50, b = 0.25 },
}

local function collect(map)
  local d = P.DB()
  local spots = {}
  local function from(entries, mine, author)
    for npc, e in pairs(entries or {}) do
      if e.locs then
        local value = P.ValuePerPick(npc) or 0
        for _, l in ipairs(e.locs) do
          if l.m == map then
            spots[#spots + 1] = { x = l.x, y = l.y, n = l.n or 1, npc = npc, name = e.name, mine = mine, author = author, value = value }
          end
        end
      end
    end
  end
  from(d.loot, true)
  if d.opts.showShared and d.opts.pinsShared then
    for uid, a in pairs(d.shared) do if uid ~= d.uid then from(a.npcs, false, uid) end end
  end
  return spots
end

local function cluster(spots)
  local out = {}
  for _, s in ipairs(spots) do
    local best, bestD
    for _, c in ipairs(out) do
      local dx, dy = c.x - s.x, c.y - s.y
      local dd = math.sqrt(dx * dx + dy * dy)
      if dd < RADIUS and (not bestD or dd < bestD) then best, bestD = c, dd end
    end
    if not best then
      best = { x = s.x, y = s.y, n = 0, sx = 0, sy = 0, vs = 0, mobs = {}, mine = false, nMine = 0, nOthers = 0, authors = {}, authorCount = 0 }
      out[#out + 1] = best
    end
    if s.mine then best.nMine = best.nMine + s.n
    else
      best.nOthers = best.nOthers + s.n
      if s.author and not best.authors[s.author] then best.authors[s.author] = true; best.authorCount = best.authorCount + 1 end
    end
    best.sx = best.sx + s.x * s.n; best.sy = best.sy + s.y * s.n; best.n = best.n + s.n
    best.x, best.y = best.sx / best.n, best.sy / best.n
    best.vs = best.vs + s.value * s.n
    best.mine = best.mine or s.mine
    local mob = best.mobs[s.npc] or { name = s.name or ("NPC " .. s.npc), n = 0, value = s.value }
    mob.n = mob.n + s.n; best.mobs[s.npc] = mob
  end
  for _, c in ipairs(out) do c.value = c.vs / math.max(c.n, 1) end
  local sorted = {}
  for i, c in ipairs(out) do sorted[i] = c end
  table.sort(sorted, function(a, b) return a.value > b.value end)
  for i, c in ipairs(sorted) do c.tier = #sorted < 3 and 1 or math.min(3, math.floor((i - 1) / (#sorted / 3)) + 1) end
  return out
end
P._cluster, P._collect = cluster, collect

if MapCanvasPinMixin and CreateFromMixins then
  KinaPocketPinMixin = CreateFromMixins(MapCanvasPinMixin)
  local M = KinaPocketPinMixin
  function M:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.2)
    self.Bubble = self:CreateTexture(nil, "BACKGROUND"); self.Bubble:SetTexture(CIRCLE); self.Bubble:SetPoint("CENTER")
    self.Ring = self:CreateTexture(nil, "BORDER"); self.Ring:SetTexture(CIRCLE); self.Ring:SetPoint("CENTER")
    self.Icon = self:CreateTexture(nil, "ARTWORK"); self.Icon:SetTexture(P.ICON); self.Icon:SetPoint("CENTER")
    local mask = self:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); mask:SetAllPoints(self.Icon)
    self.Icon:AddMaskTexture(mask)
    self.Shared = self:CreateTexture(nil, "OVERLAY"); self.Shared:SetTexture(CIRCLE)
    self.Shared:SetVertexColor(0.2, 1, 0.8, 1); self.Shared:SetPoint("CENTER", self.Ring, "TOPRIGHT", -2, -2)
  end
  function M:OnAcquired(c)
    self.cluster = c
    local t = TIERS[c.tier] or TIERS[3]
    local s = (P.DB().opts.pinScale or 100) / 100
    local bubble, icon = (26 + math.min(c.n, 30) * 0.8) * s, 16 * s
    self:SetSize(bubble, bubble)
    self.Bubble:SetSize(bubble, bubble); self.Bubble:SetVertexColor(t.r, t.g, t.b, 0.28)
    self.Ring:SetSize(icon + 5 * s, icon + 5 * s); self.Ring:SetVertexColor(t.r, t.g, t.b, 1)
    self.Icon:SetSize(icon, icon); self.Icon:SetDesaturated(not c.mine)
    self.Shared:SetSize(7 * s, 7 * s); self.Shared:SetShown(c.mine and c.nOthers > 0)
    self:SetPosition(c.x, c.y)
  end
  -- right-click passthrough is protected in combat: skip it then (as Kaydee's does)
  function M:CheckMouseButtonPassthrough(...)
    if InCombatLockdown() then return end
    if MapCanvasPinMixin.CheckMouseButtonPassthrough then MapCanvasPinMixin.CheckMouseButtonPassthrough(self, ...) end
  end
  function M:OnMouseEnter()
    local c = self.cluster
    if not c then return end
    local t = TIERS[c.tier] or TIERS[3]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|T" .. P.ICON .. ":14|t Pickpocket spot", 1, 0.82, 0)
    GameTooltip:AddLine(t.name, t.r, t.g, t.b)
    GameTooltip:AddDoubleLine("About per pick", C.Money(c.value), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Picked here (you / others)", c.nMine .. " / " .. c.nOthers, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine(" ")
    local mobs = {}
    for _, m in pairs(c.mobs) do mobs[#mobs + 1] = m end
    table.sort(mobs, function(a, b) return a.value > b.value end)
    for i, m in ipairs(mobs) do
      if i > 8 then GameTooltip:AddLine("+" .. (#mobs - 8) .. " more", 0.6, 0.6, 0.6); break end
      GameTooltip:AddDoubleLine(m.name, C.Money(m.value), 1, 1, 1, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
  end
  function M:OnMouseLeave() GameTooltip:Hide() end

  local provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate(TEMPLATE) end
  function provider:RefreshAllData()
    self:RemoveAllData()
    if not (P.Active() and P.DB().opts.pins) then return end
    local map = self:GetMap():GetMapID()
    if not map then return end
    local ok, clusters = pcall(function() return cluster(collect(map)) end)
    if not ok then return end
    for _, c in ipairs(clusters) do self:GetMap():AcquirePin(TEMPLATE, c) end
  end
  function P.RefreshPins()
    local map = provider:GetMap()
    if map and map:IsShown() then provider:RefreshAllData() end
  end
  local added = false
  C.On("PLAYER_LOGIN", function()
    if added or not (WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
    added = true
    local ok, err = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, provider)
    if not ok then C.Print("pocket map spots unavailable (" .. tostring(err) .. ").") end
  end)
  C.On("PLAYER_REGEN_ENABLED", function() pcall(P.RefreshPins) end)
end
