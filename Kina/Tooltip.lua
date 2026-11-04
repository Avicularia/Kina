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

local HEAD  = { 0.31, 0.76, 0.97 }  -- Kina blue
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
  tip:AddLine(" ")
  tip:AddLine("Kina", HEAD[1], HEAD[2], HEAD[3])

  -- Vendor
  local v, how = C.VendorPrice(id)
  if v and v > 0 then
    tip:AddDoubleLine("Vendor", C.Money(v) .. (how == "seen" and "" or " |cff999999(client)|r"),
      LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
  else
    tip:AddDoubleLine("Vendor", "no vendor value", LABEL[1], LABEL[2], LABEL[3], DIM[1], DIM[2], DIM[3])
  end

  -- Auction
  local mi, who, scanT = C.MarketItem(id)
  if r.bind == 1 or r.bind == 4 then
    tip:AddDoubleLine("Auction", "soulbound", LABEL[1], LABEL[2], LABEL[3], DIM[1], DIM[2], DIM[3])
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

  -- Disenchant (gear only)
  if C.IsGear(r) then addDE(tip, id, r) end

  -- the recommendation, with the reason
  local route, best, det = C.BestRoute(id, 1)
  if route and route ~= "KEEP" then
    local why = ""
    if route == "AUCTION" and det.deAll and not det.canDE then why = " (no enchanter set in Settings)"
    elseif route == "AUCTION" and det.de then why = " (beats disenchant)"
    elseif route == "DISENCHANT" and det.ah then why = string.format(" (AH keeps %s)", C.Money(det.ah))
    elseif route == "VENDOR" and det.ah then why = string.format(" (AH keeps only %s)", C.Money(det.ah)) end
    tip:AddDoubleLine("Best: " .. route:lower() .. why, C.Money(best), HEAD[1], HEAD[2], HEAD[3], GOLD[1], GOLD[2], GOLD[3])
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
local function handle(tip, data)
  if not C.ready or C.PUBLIC or C.settings.tooltip == false then return end -- public: prices stay behind the scenes for now
  if not tip or tip:IsForbidden() then return end
  if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end -- skip comparison tooltips
  local id = type(data) == "table" and tonumber(data.id) or nil
  if not id and tip.GetItem then
    local _, link = tip:GetItem()
    id = C.ItemIDFromLink(link)
  end
  if not id then return end
  if tip.kscItemID == id then return end -- callbacks can fire twice for one hover
  tip.kscItemID = id
  local ok, err = pcall(addLines, tip, id)
  if not ok and C.debug then C.Print("tooltip error: " .. tostring(err)) end
  tip:Show()
end

C._TooltipAdd = addLines -- for tests
local hooked = false
local function install()
  if hooked then return end
  hooked = true
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip and tip.HookScript then
      tip:HookScript("OnTooltipCleared", function(self) self.kscItemID = nil end)
    end
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, handle)
  else
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
      if tip and tip.HookScript then tip:HookScript("OnTooltipSetItem", function(self) handle(self) end) end
    end
  end
end
C.On("INIT", install)

function C.ToggleTooltip()
  C.settings.tooltip = (C.settings.tooltip == false)
  C.Print("item tooltip prices: " .. (C.settings.tooltip and "on" or "off"))
end
