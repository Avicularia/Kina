-- Kina: item tooltip prices.
-- Hovering any item (bags, bank, chests/loot, auction house, vendors, links) adds:
--   Vendor     - what a merchant pays you (learned price when Kina has seen one)
--   Auction    - lowest buyout in Kina's last scan, and what you'd net after the cut
--   Disenchant - expected net value of the materials, plus the % breakdown
-- Read-only: no AH queries, no saved-data writes beyond what C.Item already caches.
-- /kina tooltip turns it on or off.
local _, C = ...
local D = C.Data
local floor = math.floor

local HEAD  = { 1.00, 0.82, 0.35 }  -- 1.5.4: Kina gold
local LABEL = { 0.80, 0.80, 0.80 }
local GOLD  = { 1.00, 0.82, 0.00 }
local DIM   = { 0.60, 0.60, 0.60 }
local GOOD  = { 0.40, 1.00, 0.50 }
local WARN  = { 1.00, 0.55, 0.35 }

local function money(cp) return (cp and cp > 0) and C.Money(cp) or "-" end

local function matName(id)
  local r = C.Item(id)
  local name = (r and r.name) or ("item #" .. id)
  local q = r and r.q
  local col = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if col and col.hex then return col.hex .. name .. "|r" end
  return name
end

local function qtyText(lo, hi)
  if not lo then return "" end
  if hi and hi ~= lo then return string.format("x%d-%d", lo, hi) end
  if lo ~= floor(lo) then return string.format("x%.1f", lo) end
  return "x" .. lo
end

local function tier(list, il)
  for _, t in ipairs(list) do if il >= t[1] and il <= t[2] then return t end end
end

-- Breakdown rows: { mat, p, lo, hi, avg }. Uses your own disenchants when there are
-- 20+ in the band (same rule as C.DEOutcomes), otherwise the Classic table.
local function breakdown(r)
  local obs = C.db.deObs and C.db.deObs[C.DETierKey(r)]
  if C.settings.deMine and obs and obs.n and obs.n >= C.DE_OBS_MIN and obs.mats then
    local rows = {}
    for mat, n in pairs(obs.mats) do
      local avg = n / obs.n
      rows[#rows + 1] = { mat = mat, avg = avg, lo = avg, hi = avg, observed = true }
    end
    return rows, "your " .. obs.n .. " disenchants"
  end
  local il, rows = r.il, {}
  if r.q == 2 then
    local t = tier(D.deGreen, C.DELevel(r)); if not t then return nil end
    local pct = (r.cls == 2) and t[11] or t[10]
    rows[#rows + 1] = { mat = t[3], p = pct[1], lo = t[6], hi = t[7] }
    rows[#rows + 1] = { mat = t[4], p = pct[2], lo = t[8], hi = t[9] }
    if t[5] and pct[3] and pct[3] > 0 then rows[#rows + 1] = { mat = t[5], p = pct[3], lo = 1, hi = 1 } end
  elseif r.q == 3 then
    local t = tier(D.deRare, C.DELevel(r)); if not t then return nil end
    rows[#rows + 1] = { mat = t[3], p = t[4], lo = 1, hi = 1 }
    if t[5] then rows[#rows + 1] = { mat = t[5], p = t[6], lo = 1, hi = 1 } end
  elseif r.q == 4 then
    local t = tier(D.deEpic, il); if not t then return nil end
    rows[#rows + 1] = { mat = t[3], p = 1, lo = t[4], hi = t[5] }
  end
  if #rows == 0 then return nil end
  table.sort(rows, function(a, b) return (a.p or 0) > (b.p or 0) end)
  return rows, (r.q == 4) and "Classic table" or (D.deSource or "Forever guide table")
end

local function pctText(p)
  if p >= 0.995 or p == 0 then return string.format("%3.0f%%", p * 100) end
  if p < 0.01 then return string.format("%.1f%%", p * 100) end
  return string.format("%3.0f%%", p * 100)
end

local function addDE(tip, id, r)
  local ok, why = C.CanDE(id)
  if ok == false then
    -- only worth saying for gear someone might expect to disenchant
    if why == "game refuses" or why == "shirt/tabard" then
      tip:AddDoubleLine("Disenchant", "can't be disenchanted", LABEL[1], LABEL[2], LABEL[3], WARN[1], WARN[2], WARN[3])
    end
    return
  end
  if ok == nil then
    tip:AddDoubleLine("Disenchant", "item data loading...", LABEL[1], LABEL[2], LABEL[3], DIM[1], DIM[2], DIM[3])
    return
  end
  local rows, basis = breakdown(r)
  if not rows then
    tip:AddDoubleLine("Disenchant", "no table for ilvl " .. tostring(r.il), LABEL[1], LABEL[2], LABEL[3], DIM[1], DIM[2], DIM[3])
    return
  end

  local dv = C.DEValue(id)
  local ev = dv and dv.ev
  local right = ev and ev > 0 and C.Money(ev) or "no mat prices"
  if dv and dv.missing and ev and ev > 0 then right = right .. "+" end
  tip:AddDoubleLine("Disenchant (avg)", right, LABEL[1], LABEL[2], LABEL[3], GOLD[1], GOLD[2], GOLD[3])
  if dv and dv.lo and dv.hi and dv.hi > dv.lo and not dv.missing then
    tip:AddDoubleLine("   range", C.Money(dv.lo) .. " - " .. C.Money(dv.hi), DIM[1], DIM[2], DIM[3], DIM[1], DIM[2], DIM[3])
  end

  for _, row in ipairs(rows) do
    local unit = C.MatExit(row.mat)
    local avgQty = row.avg or ((row.lo + row.hi) / 2)
    local val = unit and floor(unit * avgQty) or nil
    local left = row.observed
      and string.format("   avg %s %s", qtyText(row.avg), matName(row.mat))
      or string.format("   %s  %s %s", pctText(row.p), matName(row.mat), qtyText(row.lo, row.hi))
    tip:AddDoubleLine(left, val and C.Money(val) or "no price", 1, 1, 1,
      val and GOLD[1] or DIM[1], val and GOLD[2] or DIM[2], val and GOLD[3] or DIM[3])
  end

  -- your own results, shown beside the table (they only replace it with the Settings switch on and 100+)
  local obs = C.db.deObs and C.db.deObs[C.DETierKey(r)]
  if obs and obs.n and obs.n > 0 and obs.mats and not (rows[1] and rows[1].observed) then
    local parts = {}
    for mat, n in pairs(obs.mats) do parts[#parts + 1] = string.format("%.2f %s", n / obs.n, matName(mat)) end
    tip:AddLine(string.format("   your %d disenchants here: %s each", obs.n, table.concat(parts, ", ")), DIM[1], DIM[2], DIM[3], true)
  end
  local who = C.DisenchanterText and C.DisenchanterText()
  local skillCol = who and DIM or WARN
  tip:AddDoubleLine("   " .. (who and ("disenchanter: " .. who) or "needs an enchanter (any skill)"), basis, skillCol[1], skillCol[2], skillCol[3], DIM[1], DIM[2], DIM[3])
end

local function addLines(tip, id)
  local r = C.Item(id)
  if not r then return end
  -- 1.5.4 (Taylor): one clean block, headed by the Kina coin
  tip:AddLine("|TInterface\\AddOns\\Kina\\Media\\KinaLogo:14:14|t |cffffd15aKina|r", 1, 1, 1)

  -- Vendor
  local v, how = C.VendorPrice(id)
  if v and v > 0 then
    tip:AddDoubleLine("Vendor", C.Money(v),
      LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
  else
    tip:AddDoubleLine("Vendor", "no vendor value", LABEL[1], LABEL[2], LABEL[3], DIM[1], DIM[2], DIM[3])
  end

  -- Auction
  local mi, who, scanT = C.MarketItem(id)
  if r.bind == 1 or r.bind == 4 then
    tip:AddDoubleLine("Auction", "soulbound: can't auction", LABEL[1], LABEL[2], LABEL[3], WARN[1], WARN[2], WARN[3])
  elseif mi and mi.m then
    local net, price, cut, risk = C.AHNet(id, 1)
    tip:AddDoubleLine("Auction (" .. (mi.q or mi.n or 0) .. " listed)", C.Money(mi.m), LABEL[1], LABEL[2], LABEL[3], GOOD[1], GOOD[2], GOOD[3])
    if net then
      -- what you actually keep: price used, minus the cut, minus the deposit you lose
      -- when ~30% of listings expire
      tip:AddDoubleLine(string.format("   you keep (%s - %s cut - %s deposit risk)", C.Money(price), C.Money(cut or 0), C.Money(risk or 0)),
        C.Money(net), DIM[1], DIM[2], DIM[3], GOOD[1], GOOD[2], GOOD[3])
    end
  elseif C.market.scanTime or (C.Share and next(C.Share.DB().authors)) then
    tip:AddDoubleLine("Auction", "not in last scan", LABEL[1], LABEL[2], LABEL[3], DIM[1], DIM[2], DIM[3])
  else
    tip:AddDoubleLine("Auction", "no scan yet", LABEL[1], LABEL[2], LABEL[3], DIM[1], DIM[2], DIM[3])
  end

  -- Disenchant (gear only; the breakdown can be switched off in Settings)
  if C.IsGear(r) and C.settings.tipDE ~= false then addDE(tip, id, r) end

  -- the recommendation (1.5.4: the same call as the disenchant edge rule when it can be
  -- disenchanted: DE has to beat the best sale by 10-20%)
  local d = C.DECall and C.DECall(id)
  if d then
    local name = (d.call == "disenchant" and "Disenchant") or (d.call == "auction" and "Auction house") or "Vendor"
    tip:AddDoubleLine("Best: " .. name, C.Money(d.best), GOOD[1], GOOD[2], GOOD[3], GOLD[1], GOLD[2], GOLD[3])
  else
    local route, best, det = C.BestRoute(id, 1)
    if route and route ~= "KEEP" then
      local why = ""
      local nm = (route == "AUCTION" and "Auction house") or (route == "DISENCHANT" and "Disenchant") or "Vendor"
      if route == "VENDOR" and v and v > 0 then best = v end
      tip:AddDoubleLine("Best: " .. nm .. why, C.Money(best), GOOD[1], GOOD[2], GOOD[3], GOLD[1], GOLD[2], GOLD[3])
    end
  end

  if mi and scanT then
    local age = math.max(0, floor((C.Now() - scanT) / 60))
    if who or age >= 60 then
      local whoText = who and ((Ambiguate and Ambiguate(who, "short") or who) .. "'s scan") or "your scan"
      local ageText = age < 60 and (age .. "m") or (floor(age / 60) .. "h")
      tip:AddLine(string.format("AH price from %s, %s old", whoText, ageText), DIM[1], DIM[2], DIM[3])
    end
  end
end

------------------------------------------------------------------ hooks
-- 1.5.4 (Taylor): back on in the public build, and FIRST among the add-on lines: the
-- block goes in right after the item's own sell-price line (a line hook, which runs
-- before other add-ons' whole-tooltip hooks); items without a sell price get it at the
-- end as before. One block per hover (kept in a local table, never on the tooltip).
local shown = setmetatable({}, { __mode = "k" })
-- 0.9.3: "Only Kina" rebuilds the tooltip once per hover. Rebuilding it made the game
-- (and other add-ons) fill it again, which rebuilt it again: the tooltip flashed.
local rebuilding = setmetatable({}, { __mode = "k" })
local rebuiltFor = setmetatable({}, { __mode = "k" })
local function idOf(tip, data)
  local id = type(data) == "table" and tonumber(data.id) or nil
  if not id and tip.GetItem then
    local _, link = tip:GetItem()
    if link and not (issecretvalue and issecretvalue(link)) then id = C.ItemIDFromLink(link) end
  end
  return id
end
local function handle(tip, data)
  if not C.ready or C.settings.tooltip == false then return end
  if not tip or (tip.IsForbidden and tip:IsForbidden()) then return end
  if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end -- skip comparison tooltips
  if InCombatLockdown and InCombatLockdown() then return end
  if rebuilding[tip] then return end
  local id = idOf(tip, data)
  if not id or shown[tip] == id then return end
  shown[tip] = id
  local ok, err = pcall(addLines, tip, id)
  if not ok and C.debug then C.Print("tooltip error: " .. tostring(err)) end
  tip:Show()
  if C.settings.tipOnly and C_Timer and C_Timer.After and tip.NumLines and tip.GetName and tip:GetName() then
    local keep, name = tip:NumLines(), tip:GetName()
    C_Timer.After(0, function() pcall(C.TipOnlyKina, tip, name, keep, id) end)
  end
end
-- 1.5.4 (Taylor): "the only thing I need to see is the part you added": with Settings >
-- "Only Kina in item tooltips" on, the lines other add-ons put under Kina's block are
-- dropped (the tooltip is rebuilt from the game's own lines and Kina's)
-- 0.9.8: "Only Kina" shows its OWN tooltip over the game's: the item's own lines and
-- Kina's block, copied once. The game's tooltip stays where it is, invisible, so other
-- add-ons can keep adding to it without anything being rebuilt, hidden or resized under
-- them (each of those made the tooltip flash).
local kt -- Kina's item tooltip
local active = setmetatable({}, { __mode = "k" })
local function kinaTip()
  if not kt then
    kt = CreateFrame("GameTooltip", "KinaItemTooltip", UIParent, "GameTooltipTemplate")
    kt:SetFrameStrata("TOOLTIP")
  end
  return kt
end
local function release(tip)
  if active[tip] then
    active[tip] = nil
    if kt then kt:Hide() end
    tip:SetAlpha(1)
  end
end
C._TipRelease = release
function C.TipOnlyKina(tip, name, keep, id)
  if tip ~= GameTooltip or not tip:IsShown() or shown[tip] ~= id then return end
  local rows = {}
  for i = 1, keep do
    local L, R = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
    local lt = L and L:GetText()
    if lt and issecretvalue and issecretvalue(lt) then return end
    local rt = R and R:IsShown() and R:GetText() or nil
    if rt and issecretvalue and issecretvalue(rt) then rt = nil end
    local lr, lg, lb = 1, 1, 1; if L then lr, lg, lb = L:GetTextColor() end
    local rr, rg, rb = 1, 1, 1; if R then rr, rg, rb = R:GetTextColor() end
    -- the game draws the sell price with coins next to the text: keep it as text
    if lt and SELL_PRICE and lt:find(SELL_PRICE, 1, true) and C.VendorPrice then
      local v = C.VendorPrice(id); if v and v > 0 then lt = SELL_PRICE .. " " .. C.Money(v) end
    end
    rows[i] = { lt or " ", rt, lr, lg, lb, rr, rg, rb }
  end
  local k = kinaTip()
  k:SetOwner(UIParent, "ANCHOR_NONE")
  k:ClearAllPoints(); k:SetPoint("TOPLEFT", tip, "TOPLEFT", 0, 0)
  k:ClearLines()
  for _, r in ipairs(rows) do
    if r[2] and r[2] ~= "" then k:AddDoubleLine(r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8])
    else k:AddLine(r[1], r[3], r[4], r[5], #r[1] > 48) end
  end
  k:Show()
  active[tip] = true
  tip:SetAlpha(0)
end

C._TooltipAdd = addLines -- for tests
local hooked = false
local function install()
  if hooked then return end
  hooked = true
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip and tip.HookScript then
      tip:HookScript("OnTooltipCleared", function(self) if not rebuilding[self] then shown[self] = nil; release(self) end end)
      tip:HookScript("OnHide", function(self) rebuiltFor[self] = nil; release(self) end)
      -- (a few times a second while shown: hide lines other add-ons add late)
      local acc = 0
      tip:HookScript("OnUpdate", function(self, el)
        -- (Kina's own tooltip is showing: keep the game's one invisible under it)
        if active[self] and self:GetAlpha() > 0 then self:SetAlpha(0) end
      end)
    end
  end
  local TDP = TooltipDataProcessor
  if TDP and TDP.AddLinePostCall and Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice then
    TDP.AddLinePostCall(Enum.TooltipDataLineType.SellPrice, function(tip) local _, d = pcall(function() return tip.GetPrimaryTooltipData and tip:GetPrimaryTooltipData() end); handle(tip, d) end)
  end
  if TDP and TDP.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TDP.AddTooltipPostCall(Enum.TooltipDataType.Item, handle)
  else
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
      if tip and tip.HookScript then tip:HookScript("OnTooltipSetItem", function(self) handle(self) end) end
    end
  end
end
-- registered as soon as Kina loads (not at INIT), so it runs ahead of later hooks
install()

function C.ToggleTooltip()
  C.settings.tooltip = (C.settings.tooltip == false)
  C.Print("item tooltip prices: " .. (C.settings.tooltip and "on" or "off"))
end
