-- Kina 2.0: Prices, an auction house browser that works anywhere (Taylor: "research items
-- and look up prices based on my last scan while I'm flying or running around").
-- Laid out like the AH's own Browse tab: categories on the left, search, level and
-- quality filters, sortable columns. Prices come from your last scan plus the scans other
-- Kinas share (the freshest one that lists the item). Research only: nothing here buys,
-- bids or posts, and it never touches the real auction house or another AH addon.
local _, C = ...
local P = {}
C.Prices = P

local ROWS, ROW_H = 16, 20 -- (2.0: 18 ran into the info panel)
local CAT_ROWS = 21
local W, H = 860, 540
local GOLD, GREY, WHITE = "|cffffc54a", "|cff9d9d9d", "|cffffffff"

-- the AH's own categories: Blizzard's AuctionCategories, the same table its Browse tab
-- (and ForeverForge) is built from, so names, order and nesting are identical. It lives in
-- the game's AH addon, loaded here if the AH hasn't been opened yet this session.
local function blizzCats()
  if not _G.AuctionCategories then
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "Blizzard_AuctionHouseUI") end
  end
  return _G.AuctionCategories
end
P.BlizzCats = blizzCats
local function skipCat(cat)
  return cat.HasFlag and (cat:HasFlag("WOW_TOKEN_FLAG") or cat:HasFlag("WOW_TOKEN"))
end
-- the item's inventory type (a number, as the AH's filters use)
local function invType(e)
  local r = e.r or {}
  if r.inv == nil and C_Item and C_Item.GetItemInventoryTypeByID then
    local ok, v = pcall(C_Item.GetItemInventoryTypeByID, e.id)
    r.inv = (ok and v) or false
  end
  return r.inv or nil
end
local POOR = Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.PoorQuality
-- does an item belong in an AH category (any of its filters; nil fields match anything)
local function inCat(e, cat)
  local r = e.r or {}
  if cat.implicitFilter and POOR and cat.implicitFilter == POOR and (r.q or -1) ~= 0 then return false end
  local fl = cat.filters
  if not fl or #fl == 0 then return true end
  for _, f in ipairs(fl) do
    if (f.classID == nil or f.classID == r.cls) and (f.subClassID == nil or f.subClassID == r.sub)
      and (f.inventoryType == nil or f.inventoryType == invType(e)) then return true end
  end
  return false
end
P.InCat = inCat
-- (no AH table in this client: the old grouping by item class)
local CATS = { 2, 4, 1, 0, 7, 6, 11, 9, 5, 12, 15 }
local CAT_NAME = { [0] = "Consumables", [1] = "Containers", [2] = "Weapons", [4] = "Armor", [5] = "Reagents",
  [6] = "Projectiles", [7] = "Trade Goods", [9] = "Recipes", [11] = "Quivers", [12] = "Quest Items", [15] = "Miscellaneous" }
local function fallbackCats()
  local out = {}
  for _, cls in ipairs(CATS) do out[#out + 1] = { name = CAT_NAME[cls], filters = { { classID = cls } } } end
  return out
end
local QUAL = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local QCOL = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }

local state = { cat = nil, path = nil, expanded = {}, catOffset = 0, text = "", minL = nil, maxL = nil, minQ = nil, sort = "name", desc = false, offset = 0, sel = nil }
P.state = state

------------------------------------------------------------------ the data
-- every item any scan Kina holds has a price for: { id, r = item record, mi = market row, who, t }
local cache, cacheAt
local function collect()
  local now = GetTime and GetTime() or 0
  if cache and cacheAt and now - cacheAt < 10 then return cache end
  local ids = {}
  for id in pairs(C.market and C.market.items or {}) do ids[id] = true end
  local S = C.Share
  local d = S and S.DB and S.DB()
  local mk = C.MarketKey and C.MarketKey()
  for _, a in pairs(d and d.authors or {}) do
    local m = a.market
    if m and m.mkey == mk and m.items then for id in pairs(m.items) do ids[id] = true end end
  end
  local out = {}
  for id in pairs(ids) do
    local mi, who, t
    if S and S.MarketItem then mi, who, t = S.MarketItem(id) end
    if not mi then mi = C.market.items and C.market.items[id]; t = C.market.scanTime end
    if mi and (mi.m or mi.md or mi.d) then
      local r = C.Item(id)
      out[#out + 1] = { id = id, r = r, mi = mi, who = who, t = t }
    end
  end
  cache, cacheAt = out, now
  return out
end
function P.Invalidate() cache = nil end

local function lowest(e) return e.mi.m or e.mi.d or e.mi.md or 0 end
local function typical(e) return e.mi.md or e.mi.d or e.mi.m or 0 end
local function vendor(e) return (C.VendorPrice and C.VendorPrice(e.id)) or 0 end
local function level(e) return (e.r and (e.r.rl or 0)) or 0 end
local function qual(e) return (e.r and e.r.q) or -1 end
local function name(e) return (e.r and e.r.name) or ("item " .. e.id) end

local SORTS = {
  name = function(a, b) return name(a):lower() < name(b):lower() end,
  lvl = function(a, b) return level(a) < level(b) end,
  qty = function(a, b) return (a.mi.q or 0) < (b.mi.q or 0) end,
  low = function(a, b) return lowest(a) < lowest(b) end,
  typ = function(a, b) return typical(a) < typical(b) end,
  vend = function(a, b) return vendor(a) < vendor(b) end,
}

function P.List()
  local text = (state.text or ""):lower()
  local out = {}
  for _, e in ipairs(collect()) do
    local r = e.r or {}
    local ok = true
    if state.cat and not inCat(e, state.cat) then ok = false end
    if ok and text ~= "" and not name(e):lower():find(text, 1, true) then ok = false end
    if ok and state.minL and level(e) < state.minL then ok = false end
    if ok and state.maxL and level(e) > state.maxL then ok = false end
    if ok and state.minQ and qual(e) < state.minQ then ok = false end
    if ok then out[#out + 1] = e end
  end
  local f = SORTS[state.sort] or SORTS.name
  table.sort(out, function(a, b)
    if state.desc then return f(b, a) end
    return f(a, b)
  end)
  return out
end

local function ago(t)
  if not t or t <= 0 then return "never" end
  local s = math.max(0, (C.Now and C.Now() or time()) - t)
  if s < 3600 then return math.floor(s / 60) .. "m ago" end
  if s < 86400 then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / 86400) .. "d ago"
end

------------------------------------------------------------------ the window
local f
local function btn(parent, text, w, h, fn)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h or 20); b:SetText(text)
  if C.Skin and C.Skin.Button then C.Skin.Button(b) end
  b:SetScript("OnClick", fn)
  return b
end
local function edit(parent, w, numeric)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, 20); e:SetAutoFocus(false)
  if numeric and e.SetNumeric then e:SetNumeric(true) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

local function build()
  if f then return f end
  f = CreateFrame("Frame", "KinaPrices", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(W, H); f:SetPoint("CENTER", 0, 20)
  f:SetFrameStrata("HIGH"); f:SetToplevel(true); f:SetClampedToScreen(true)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); if C.SavePos then C.SavePos(self, "prices") end end)
  if C.RestorePos then C.RestorePos(f, "prices", "CENTER", UIParent, "CENTER", 0, 20) end
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.04, 0.035, 0.03, 0.97); f:SetBackdropBorderColor(0.86, 0.6, 0.2, 1)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 14, -12)
  if C.Cos and C.Cos.Font then C.Cos.Font(title, 15, "") end
  title:SetText(GOLD .. "Kina prices|r"); title:SetTextColor(1, 0.78, 0.34)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.sub:SetPoint("LEFT", title, "RIGHT", 12, 0)
  local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -4, -4)

  -- filters row (like the AH's Browse tab)
  local nl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); nl:SetPoint("TOPLEFT", 16, -42); nl:SetText("Name")
  f.search = edit(f, 190); f.search:SetPoint("TOPLEFT", 16, -56)
  f.search:SetScript("OnTextChanged", function(self) state.text = self:GetText() or ""; state.offset = 0; P.Draw() end)
  local ll = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ll:SetPoint("TOPLEFT", 226, -42); ll:SetText("Level range")
  f.minL = edit(f, 34, true); f.minL:SetPoint("TOPLEFT", 228, -56)
  local dash = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); dash:SetPoint("LEFT", f.minL, "RIGHT", 4, 0); dash:SetText("-")
  f.maxL = edit(f, 34, true); f.maxL:SetPoint("LEFT", dash, "RIGHT", 8, 0)
  local function levels()
    state.minL = tonumber(f.minL:GetText() or ""); state.maxL = tonumber(f.maxL:GetText() or ""); state.offset = 0; P.Draw()
  end
  f.minL:SetScript("OnTextChanged", levels); f.maxL:SetScript("OnTextChanged", levels)
  local ql = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ql:SetPoint("TOPLEFT", 330, -42); ql:SetText("Rarity")
  f.qual = btn(f, "All", 96, 20, function()
    if state.minQ == nil then state.minQ = 0 elseif state.minQ >= 5 then state.minQ = nil else state.minQ = state.minQ + 1 end
    state.offset = 0; P.Draw()
  end)
  f.qual:SetPoint("TOPLEFT", 330, -56)
  f.reset = btn(f, "Reset", 70, 20, function()
    state.cat, state.path, state.text, state.minL, state.maxL, state.minQ, state.offset, state.sel = nil, nil, "", nil, nil, nil, 0, nil
    state.expanded, state.catOffset = {}, 0
    f.search:SetText(""); f.minL:SetText(""); f.maxL:SetText(""); P.Draw()
  end)
  f.reset:SetPoint("LEFT", f.qual, "RIGHT", 8, 0)
  f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.count:SetPoint("TOPRIGHT", -18, -60)

  -- categories (left)
  f.catBtns = {}
  for i = 1, CAT_ROWS do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(150, 16); b:SetPoint("TOPLEFT", 14, -92 - (i - 1) * 16)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", 4, 0); b.t:SetJustifyH("LEFT"); b.t:SetWidth(144)
    b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:SetColorTexture(0.86, 0.6, 0.2, 0.22); b.hl:Hide()
    b:SetScript("OnEnter", function(self) if not self.sel then self.hl:Show() end end)
    b:SetScript("OnLeave", function(self) if not self.sel then self.hl:Hide() end end)
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(_, d) P.ScrollCats(d) end)
    b:SetScript("OnClick", function(self)
      local node = self.node
      if not node then state.cat, state.path = nil, nil
      elseif state.path == node.path then
        -- the selected one again: unselect and fold it (as the AH does)
        state.cat, state.path = nil, nil; state.expanded[node.path] = nil
      else
        state.cat, state.path = node.cat, node.path
        if node.cat.subCategories then state.expanded[node.path] = true end
      end
      state.offset = 0; P.Draw()
    end)
    f.catBtns[i] = b
  end
  local vline = f:CreateTexture(nil, "ARTWORK"); vline:SetColorTexture(0.52, 0.35, 0.11, 0.8); vline:SetWidth(1)
  vline:SetPoint("TOPLEFT", 172, -88); vline:SetPoint("BOTTOMLEFT", 172, 104)

  -- column headers (click to sort; again to reverse)
  local COLS = {
    { key = "name", label = "Item", x = 182, w = 270 },
    { key = "lvl", label = "Lvl", x = 456, w = 40 },
    { key = "qty", label = "Available", x = 500, w = 70 },
    { key = "low", label = "Lowest", x = 574, w = 92 },
    { key = "typ", label = "Typical", x = 670, w = 92 },
    { key = "vend", label = "Vendor", x = 766, w = 80 },
  }
  P.COLS = COLS
  f.heads = {}
  for _, c in ipairs(COLS) do
    local h = CreateFrame("Button", nil, f)
    h:SetSize(c.w, 18); h:SetPoint("TOPLEFT", c.x, -88)
    h.t = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h.t:SetAllPoints()
    h.t:SetJustifyH(c.key == "name" and "LEFT" or "RIGHT")
    h:SetScript("OnClick", function()
      if state.sort == c.key then state.desc = not state.desc else state.sort, state.desc = c.key, (c.key ~= "name" and c.key ~= "lvl") and false or false end
      state.offset = 0; P.Draw()
    end)
    h.key, h.label = c.key, c.label
    f.heads[#f.heads + 1] = h
  end
  local hline = f:CreateTexture(nil, "ARTWORK"); hline:SetColorTexture(0.52, 0.35, 0.11, 0.8); hline:SetHeight(1)
  hline:SetPoint("TOPLEFT", 180, -107); hline:SetPoint("TOPRIGHT", -14, -107)

  -- rows
  f.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(W - 196, ROW_H); r:SetPoint("TOPLEFT", 180, -110 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0)
    r.hl = r:CreateTexture(nil, "BORDER"); r.hl:SetAllPoints(); r.hl:SetColorTexture(0.86, 0.6, 0.2, 0.2); r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0)
    r.cells = {}
    for k, c in ipairs(COLS) do
      local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      local x0 = c.x - 180 + (k == 1 and 22 or 0)
      fs:SetPoint("LEFT", r, "LEFT", x0, 0); fs:SetWidth(c.w - (k == 1 and 22 or 0))
      fs:SetJustifyH(k == 1 and "LEFT" or "RIGHT")
      if fs.SetWordWrap then fs:SetWordWrap(false) end
      r.cells[k] = fs
    end
    r:SetScript("OnEnter", function(self)
      self.hl:Show()
      if self.e and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.e.id)
        GameTooltip:Show()
      end
    end)
    r:SetScript("OnLeave", function(self) if state.sel ~= (self.e and self.e.id) then self.hl:Hide() end; if GameTooltip then GameTooltip:Hide() end end)
    r:SetScript("OnClick", function(self)
      if not self.e then return end
      if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
        local _, link = GetItemInfo and GetItemInfo(self.e.id)
        if link then ChatEdit_InsertLink(link) end
        return
      end
      state.sel = self.e.id; P.Draw()
    end)
    f.rows[i] = r
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, d)
    local n = #(P.lastList or {})
    state.offset = math.max(0, math.min(math.max(0, n - ROWS), state.offset - d * 3)); P.Draw()
  end)

  -- the selected item, in full (bottom)
  local bline = f:CreateTexture(nil, "ARTWORK"); bline:SetColorTexture(0.52, 0.35, 0.11, 0.8); bline:SetHeight(1)
  bline:SetPoint("BOTTOMLEFT", 12, 100); bline:SetPoint("BOTTOMRIGHT", -12, 100)
  f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.detail:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 16, 94); f.detail:SetWidth(W - 32); f.detail:SetJustifyH("LEFT"); f.detail:SetSpacing(3)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("BOTTOMRIGHT", -16, 10)
  hint:SetText("Click an item for its listings  |  Shift-click links it in chat  |  research only: buy and post at the AH  |  /kp to open, /kp name to search")

  tinsert(UISpecialFrames, "KinaPrices")
  f:Hide()
  return f
end

local function money(cp) if not cp or cp <= 0 then return GREY .. "-|r" end; return C.Money(cp) end

function P.Draw()
  if not (f and f:IsShown()) then return end
  -- categories: the AH's own tree; the open ones list what's under them
  local nodes = { { all = true } }
  local function add(list, depth, prefix)
    for k, cat in ipairs(list or {}) do
      if not skipCat(cat) then
        local path = prefix and (prefix .. "." .. k) or tostring(k)
        nodes[#nodes + 1] = { cat = cat, depth = depth, path = path }
        if depth < 2 and state.expanded[path] then add(cat.subCategories, depth + 1, path) end
      end
    end
  end
  add(blizzCats() or fallbackCats(), 0, nil)
  P.catNodes = nodes
  state.catOffset = math.max(0, math.min(state.catOffset or 0, math.max(0, #nodes - CAT_ROWS)))
  for k, b in ipairs(f.catBtns) do
    local node = nodes[k + state.catOffset]
    if node then
      local sel = node.all and state.cat == nil or (node.path and node.path == state.path)
      b.node = (not node.all) and node or nil
      local text = node.all and "All items" or (node.cat.name or "?")
      b.t:SetText(string.rep("   ", node.depth or 0) .. (sel and GOLD or (node.depth and node.depth > 0 and "|cffd8d0c0" or WHITE)) .. text .. "|r")
      b.sel = sel
      if sel then b.hl:Show() else b.hl:Hide() end
      b:Show()
    else b:Hide(); b.node = nil end
  end
  -- headers: the sorted one shows its direction
  for _, h in ipairs(f.heads) do
    h.t:SetText((state.sort == h.key and GOLD or "|cffd9b36a") .. h.label .. (state.sort == h.key and (state.desc and " v" or " ^") or "") .. "|r")
  end
  f.qual:SetText(state.minQ and (QCOL[state.minQ] .. QUAL[state.minQ] .. "|r+") or "All")
  local list = P.List()
  P.lastList = list
  state.offset = math.max(0, math.min(state.offset, math.max(0, #list - ROWS)))
  f.count:SetText(#list == 0 and "no items" or string.format("%d-%d of %d", state.offset + 1, math.min(#list, state.offset + ROWS), #list))
  -- where the prices come from: your scan and the newest one shared with you
  local own = C.market and C.market.scanTime
  local sharedT, sharedWho
  local d = C.Share and C.Share.DB and C.Share.DB()
  local mk = C.MarketKey and C.MarketKey()
  for _, a in pairs(d and d.authors or {}) do
    local m = a.market
    if m and m.mkey == mk and (m.t or 0) > (sharedT or 0) then sharedT, sharedWho = m.t, a.name end
  end
  local bits = {}
  bits[#bits + 1] = own and ("your scan " .. ago(own)) or "no scan of yours yet"
  if sharedT and (not own or sharedT > own) then bits[#bits + 1] = "newest: " .. tostring(sharedWho and sharedWho:match("^([^%-]+)") or "another Kina") .. "'s, " .. ago(sharedT) end
  f.sub:SetText(GREY .. table.concat(bits, "   |   ") .. "|r")
  for k, r in ipairs(f.rows) do
    local e = list[state.offset + k]
    r.e = e
    if e then
      local q = qual(e)
      -- (2.0.5: GetItemIcon needs the item loaded; GetItemInfoInstant answers at once)
      local tex
      if GetItemInfoInstant then tex = select(5, GetItemInfoInstant(e.id)) end
      if not tex and C_Item and C_Item.GetItemIconByID then tex = C_Item.GetItemIconByID(e.id) end
      if not tex and GetItemIcon then tex = GetItemIcon(e.id) end
      r.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
      r.cells[1]:SetText((QCOL[q] or WHITE) .. name(e) .. "|r")
      r.cells[2]:SetText(level(e) > 0 and tostring(level(e)) or "")
      r.cells[3]:SetText(tostring(e.mi.q or 0))
      r.cells[4]:SetText(money(lowest(e)))
      r.cells[5]:SetText(money(typical(e)))
      r.cells[6]:SetText(money(vendor(e)))
      if state.sel == e.id then r.hl:Show() else r.hl:Hide() end
      r:Show()
    else r:Hide() end
  end
  -- the selected item
  local sel
  for _, e in ipairs(list) do if e.id == state.sel then sel = e; break end end
  if not sel then for _, e in ipairs(collect()) do if e.id == state.sel then sel = e; break end end end
  if sel then
    local mi = sel.mi
    local steps = {}
    for n, st in ipairs(mi.l or {}) do
      if n > 8 then break end
      steps[#steps + 1] = (st[2] or 1) .. " at " .. C.Money(st[1])
    end
    local de = C.DEValue and C.DEValue(sel.id)
    local src = sel.who and ("from " .. sel.who .. "'s scan, " .. ago(sel.t)) or ("your scan, " .. ago(sel.t))
    f.detail:SetText(table.concat({
      (QCOL[qual(sel)] or WHITE) .. name(sel) .. "|r" .. GREY .. "   (" .. src .. ")|r",
      GOLD .. "Cheapest listings:|r " .. (#steps > 0 and table.concat(steps, ",  ") or "none listed"),
      GOLD .. "Available:|r " .. (mi.q or 0) .. " in " .. (mi.n or 0) .. " listings   " .. GOLD .. "Lowest:|r " .. money(lowest(sel))
        .. "   " .. GOLD .. "Typical:|r " .. money(typical(sel)) .. "   " .. GOLD .. "Vendor:|r " .. money(vendor(sel))
        .. ((type(de) == "number" and de > 0) and ("   " .. GOLD .. "Disenchant:|r " .. C.Money(de)) or ""),
    }, "\n"))
  else
    f.detail:SetText(GREY .. "Pick an item to see its cheapest listings and where its price came from.|r")
  end
end

function P.ScrollCats(d)
  local n = #(P.catNodes or {})
  state.catOffset = math.max(0, math.min(math.max(0, n - CAT_ROWS), (state.catOffset or 0) - d * 3))
  P.Draw()
end

function P.Open(text)
  build()
  P.Invalidate()
  f:Show()
  -- 2.0.20: in front of Kina's main window (Layers.lua raises it after the main window)
  if C.RaiseKina then C.RaiseKina() else f:Raise() end
  if type(text) == "string" and f.search then f.search:SetText(text) end
  -- 2.1.0: the My bags and Transport tabs (PricesBags.lua)
  if C.PricesBags then
    pcall(C.PricesBags.Attach, f)
    if type(text) == "string" and text ~= "" then C.PricesBags.Show("browse") else C.PricesBags.Draw() end
  end
  P.Draw()
end
function P.Toggle()
  build()
  if f:IsShown() then f:Hide() else P.Open() end
end
P.Frame = function() return f end
if C.OnMarket then C.OnMarket(function() P.Invalidate(); if f and f:IsShown() then P.Draw(); if C.PricesBags then C.PricesBags.Draw() end end end) end
