-- Kina: Quick scan (button on the Deals page).
-- The full scan downloads every listing but the game allows it only every 15
-- minutes. A browse search instead returns each item's cheapest price and how many
-- are listed, page by page, as fast as the auction house answers. Used to catch
-- fresh listings under vendor price between full scans. If Forever wants a click
-- per page, the button says so: click it again for each page.
local _, C = ...
local Q = { active = false, items = {}, n = 0, pages = 0 }
C.Quick = Q
local AH = C_AuctionHouse
local function now() return GetTime and GetTime() or 0 end

local function count()
  local n = 0
  for _ in pairs(Q.items) do n = n + 1 end
  return n
end

local function finish(reason)
  if not Q.active then return end
  Q.active, Q.needClick = false, false
  local secs = now() - (Q.t0 or now())
  local found = {}
  for id, e in pairs(Q.items) do
    local v = C.VendorPrice and C.VendorPrice(id, true)
    if v and v > 0 and e.m and e.m < v then found[#found + 1] = { id = id, m = e.m, v = v, q = e.q, gain = v - e.m } end
  end
  table.sort(found, function(a, b) return a.gain > b.gain end)
  C.market.quick = { t = C.Now(), items = Q.items, complete = (reason == nil) }
  Q.last = { n = count(), pages = Q.pages, secs = secs, found = found, reason = reason, t = C.Now() }
  C.Print(string.format("quick scan: %d items in %d page%s, %.1f s%s. %d listed under vendor price right now.",
    Q.last.n, Q.pages, Q.pages == 1 and "" or "s", secs, reason and (" (" .. reason .. ")") or "", #found))
  for i = 1, math.min(5, #found) do
    local f = found[i]
    C.Print(string.format("   %s: cheapest %s, a vendor pays %s (+%s each)", (C.ItemLink and C.ItemLink(f.id)) or ("item " .. f.id),
      C.Money(f.m), C.Money(f.v), C.Money(f.gain)))
  end
  if C.Refresh then C.Refresh() end
end
Q.Finish = finish

local function read()
  if not (AH and AH.GetBrowseResults) then return end
  local ok, list = pcall(AH.GetBrowseResults)
  if not ok or type(list) ~= "table" then return end
  for _, r in ipairs(list) do
    local id = r.itemKey and r.itemKey.itemID
    if id and r.minPrice and r.minPrice > 0 then
      local e = Q.items[id]
      if not e or r.minPrice < (e.m or math.huge) then Q.items[id] = { m = r.minPrice, q = r.totalQuantity } end
    end
  end
end

local function more()
  if AH.HasFullBrowseResults and AH.HasFullBrowseResults() then finish(); return end
  Q.waiting = now()
  local ok = pcall(AH.RequestMoreBrowseResults)
  if not ok then Q.needClick = true end
end

local function onResults()
  if not Q.active then return end
  Q.pages = Q.pages + 1
  read()
  more()
  if C.Refresh then C.Refresh() end
end
C.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onResults)
C.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", onResults)
C.On("AUCTION_HOUSE_CLOSED", function() if Q.active then finish("auction house closed") end end)

-- no answer for 4 s: Forever wants a click for the next page (or the search ended)
local watch = CreateFrame("Frame")
watch:SetScript("OnUpdate", function()
  if not Q.active or Q.needClick then return end
  local t = now()
  if t - (Q.t0 or t) > 180 then finish("stopped after 3 minutes"); return end
  if Q.waiting and t - Q.waiting > 4 then
    if Q.pages == 0 then finish("no answer from the auction house") else Q.needClick = true; if C.Refresh then C.Refresh() end end
  end
end)

-- the button: start, load the next page when a click is needed, or stop
function Q.Click()
  if not C.ahOpen then C.Print("quick scan: open the auction house first."); return end
  if not (AH and AH.SendBrowseQuery) then C.Print("quick scan: this auction house has no browse search."); return end
  if Q.active then
    if Q.needClick then Q.needClick = false; Q.waiting = now(); pcall(AH.RequestMoreBrowseResults) else finish("stopped") end
    return
  end
  Q.active, Q.items, Q.pages, Q.t0, Q.needClick, Q.waiting = true, {}, 0, now(), false, now()
  local sorts = {}
  if Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price then
    sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  end
  local ok, err = pcall(AH.SendBrowseQuery, { searchString = "", sorts = sorts, filters = {}, itemClassFilters = {} })
  if not ok then Q.active = false; C.Print("quick scan: the auction house refused the search (" .. tostring(err) .. ")") end
end

function Q.ButtonText()
  if Q.active then
    if Q.needClick then return string.format("|cffffc94aQuick scan: click for page %d|r", Q.pages + 1) end
    return string.format("|cff7CFC00Quick scan: %d items...|r", count())
  end
  if Q.last then return string.format("Quick scan (%d under vendor)", #Q.last.found) end
  return "Quick scan"
end
