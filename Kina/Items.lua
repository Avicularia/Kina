-- Kina: item facts with asynchronous loading.
-- Kina Scout lost two-thirds of gear because it read scan rows before the client
-- had item data. Here every item is resolved by ID and loaded on demand.
local _, C = ...
local pending, waiting = {}, 0

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local Request = C_Item and C_Item.RequestLoadItemDataByID

local function store(id)
  local name, _, q, il, rl, _, _, _, eq, _, vend, cls, sub, bind = GetInfo(id)
  if not name then return nil end
  local r = C.db.items[id] or {}
  r.name, r.q, r.il, r.rl, r.eq, r.vend, r.cls, r.sub, r.bind = name, q, il, rl, eq, vend, cls, sub, bind
  C.db.items[id] = r
  return r
end

-- Returns the cached record (possibly partial) and whether it is complete.
function C.Item(id)
  if type(id) ~= "number" then return nil, false end
  local r = C.db.items[id]
  if r and r.name then return r, true end
  r = store(id)
  if r then return r, true end
  -- class is available instantly even when the item is not cached
  if GetInstant then
    local _, _, _, eq, _, cls, sub = GetInstant(id)
    if cls then
      r = C.db.items[id] or {}
      r.cls, r.sub, r.eq = cls, sub, eq
      C.db.items[id] = r
    end
  end
  if not pending[id] then
    pending[id] = true; waiting = waiting + 1
    if Request then pcall(Request, id) end
  end
  return r, false
end

function C.ItemsWaiting() return waiting end

C.On("GET_ITEM_INFO_RECEIVED", function(_, id, ok)
  if not pending[id] then return end
  pending[id] = nil; waiting = math.max(0, waiting - 1)
  if ok ~= false then store(id) end
  if waiting == 0 and C.OnItemsLoaded then C.OnItemsLoaded() end
end)

-- Load many items without flooding the client: 40 requests per frame.
function C.LoadItems(ids, done, progress)
  local i = 1
  C.Job(function()
    local n = 0
    while i <= #ids and n < 40 do
      C.Item(ids[i]); i = i + 1; n = n + 1
    end
    if progress then progress(i - 1) end
    if i > #ids then
      if done then
        -- give the client up to 10s to answer, then continue with what loaded
        local started = C.Now()
        C.Job(function()
          if waiting == 0 or C.Now() - started > 10 then done(); return true end
        end)
      end
      return true
    end
  end)
end

function C.IsGear(r) return r and (r.cls == 2 or r.cls == 4) end
