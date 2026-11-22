-- Kina 2.0: account net worth (Taylor: "net worth tracked including all characters on that
-- account, with each character also a separate stat"). Per character: gold, plus the items
-- in its bags and bank that aren't soulbound, at today's prices. Not counted: the mailbox,
-- soulbound items, worn gear. Each character's snapshot is saved when you play it (the bank
-- when you open it), so the total covers every character you've logged in with Kina.
local _, C = ...
local NW = {}
C.NetWorth = NW

local function soulbound(bag, slot, info, id)
  if type(info) == "table" and info.isBound ~= nil then return info.isBound end
  if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
    local ok, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if ok and loc then local ok2, b = pcall(C_Item.IsBound, loc); if ok2 and b ~= nil then return b end end
  end
  return C.IsBound and C.IsBound(id) or false
end
-- the unbound items in these bags: { [itemID] = count }
function NW.Count(bags)
  local out, CT = {}, C_Container
  if not (CT and CT.GetContainerNumSlots and CT.GetContainerItemInfo) then return out end
  for _, bag in ipairs(bags) do
    local ok, slots = pcall(CT.GetContainerNumSlots, bag)
    for slot = 1, (ok and slots) or 0 do
      local info = CT.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not soulbound(bag, slot, info, info.itemID) then
        out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return out
end

local bankOpen = false
function NW.Snapshot(withBank)
  local ch = C.char
  if not ch then return end
  ch.nw = ch.nw or {}
  ch.nw.gold = GetMoney and GetMoney() or ch.nw.gold or 0
  ch.nw.bags = NW.Count(C.PlayerBags())
  if withBank and bankOpen then ch.nw.bank = NW.Count(C.BankBags()) end
  ch.nw.t = C.Now()
end
local pending = false
local function soon(withBank)
  if pending then return end
  pending = true
  if C.After then C.After(3, function() pending = false; pcall(NW.Snapshot, withBank or bankOpen) end)
  else pending = false; pcall(NW.Snapshot, withBank) end
end
C.On("PLAYER_LOGIN", function() soon() end)
C.On("PLAYER_MONEY", function() soon() end)
C.On("BAG_UPDATE_DELAYED", function() soon() end)
C.On("BANKFRAME_OPENED", function() bankOpen = true; soon(true) end)
C.On("BANKFRAME_CLOSED", function() bankOpen = false end)
C.On("PLAYERBANKSLOTS_CHANGED", function() soon(true) end)
C.On("PLAYER_LOGOUT", function() pcall(NW.Snapshot, bankOpen) end)

-- one item's worth: what Kina would count it as in a farm (AH after the cut, disenchant or vendor)
local function worth(id)
  if not C.FarmValue then return 0 end
  local ok, v = pcall(C.FarmValue, id)
  return (ok and tonumber(v)) or 0
end
local function itemsWorth(list)
  local t = 0
  for id, n in pairs(list or {}) do t = t + worth(id) * n end
  return t
end
-- every character: { name, gold, items, total, t }, richest first; and the account total (copper)
function NW.All()
  local list, total = {}, 0
  for key, ch in pairs(C.db and C.db.chars or {}) do
    if ch.nw then
      local items = itemsWorth(ch.nw.bags) + itemsWorth(ch.nw.bank)
      local row = { name = key:match("^([^%-]+)") or key, gold = ch.nw.gold or 0, items = items, t = ch.nw.t, bank = ch.nw.bank ~= nil }
      row.total = row.gold + row.items
      list[#list + 1] = row
      total = total + row.total
    end
  end
  table.sort(list, function(a, b) return a.total > b.total end)
  return list, total
end
function NW.Total() local _, t = NW.All(); return t end
-- "Hybana 20g, Deputize 15g"
function NW.Breakdown(short)
  local list = NW.All()
  local parts = {}
  for _, r in ipairs(list) do parts[#parts + 1] = r.name .. " " .. short(r.total / 10000) end
  return table.concat(parts, ", ")
end
