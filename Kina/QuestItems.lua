-- Kina 2.0.11: quest items in the tooltip.
-- Taylor: "When I scroll over a quest item, I want to see what quest it is for, what zone
-- thats in, and if I still have the quest or not, and what level the quest is. Color the
-- quest level the same way wow does based on players level relative to it."
-- Kina reads your quest log: every objective that needs an item ("Raptor Flesh: 3/10")
-- ties that item to its quest, with the quest's level and the zone heading it sits under.
-- What Kina has seen is remembered (per realm profile), so an item whose quest you've
-- turned in or dropped still says which quest it was for: "not in your quest log".
-- Items that start a quest (in your bags) are read from the game as well.
local _, C = ...
local Q = {}
C.QuestItems = Q

local live = {}  -- [item name, lower] = { {title, level, zone, have, need, done, qid}, ... } from the log now
local function store()
  C.db.questItems = type(C.db.questItems) == "table" and C.db.questItems or {}
  return C.db.questItems -- [item name, lower] = { [quest title] = { lvl, zone, qid, t } }
end

function Q.Scan()
  if not (GetNumQuestLogEntries and GetQuestLogTitle) then return end
  local out, zone = {}, nil
  local n = GetNumQuestLogEntries() or 0
  for i = 1, n do
    local title, level, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
    if isHeader then zone = title
    elseif title then
      local nb = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
      for j = 1, nb do
        local text, kind, finished = GetQuestLogLeaderBoard(j, i)
        if kind == "item" and type(text) == "string" then
          local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
          name = name or text:match("^(.-):") or text
          local key = name:lower()
          out[key] = out[key] or {}
          table.insert(out[key], { title = title, level = level, zone = zone, have = tonumber(have), need = tonumber(need),
            done = finished or isComplete == 1, qid = qid })
          if C.db then
            local s = store()
            s[key] = s[key] or {}
            s[key][title] = { lvl = level, zone = zone, qid = qid, t = C.Now() }
          end
        end
      end
    end
  end
  live = out
end

-- the WoW colour for a quest of this level, for you (grey, green, yellow, orange, red)
local function levelColor(lvl)
  if GetQuestDifficultyColor then
    local ok, c = pcall(GetQuestDifficultyColor, lvl)
    if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
  end
  local me = (UnitLevel and UnitLevel("player")) or 1
  local d = lvl - me
  if d >= 5 then return 1, 0.1, 0.1 elseif d >= 3 then return 1, 0.5, 0.25
  elseif d >= -2 then return 1, 1, 0 end
  local grey = me <= 5 and 0 or (me <= 39 and (me - 5 - math.floor(me / 10)) or (me - 1 - math.floor(me / 5)))
  if lvl > grey then return 0.25, 0.75, 0.25 end
  return 0.5, 0.5, 0.5
end
local function hex(r, g, b)
  local function c(v) return math.floor(math.max(0, math.min(1, v or 1)) * 255 + 0.5) end
  return string.format("|cff%02x%02x%02x", c(r), c(g), c(b))
end

-- a quest-starting item in your bags: its quest ID and whether you have the quest
local function starter(id)
  local CC = C_Container
  if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemID and CC.GetContainerItemQuestInfo) then return nil end
  for bag = 0, 4 do
    for slot = 1, CC.GetContainerNumSlots(bag) or 0 do
      if CC.GetContainerItemID(bag, slot) == id then
        local ok, info = pcall(CC.GetContainerItemQuestInfo, bag, slot)
        if ok and type(info) == "table" and info.questID then return info.questID, info.isActive end
      end
    end
  end
end

-- adds the quest lines for this item to a tooltip; true if it added any
function Q.Lines(tip, id)
  local name = GetItemInfo and GetItemInfo(id)
  if not name then return false end
  local key = name:lower()
  local added = false
  local function questLine(title, lvl, zone, state, sr, sg, sb)
    local r, g, b = levelColor(lvl or 1)
    tip:AddDoubleLine("Quest: |cffffffff" .. title .. "|r", hex(r, g, b) .. "Level " .. tostring(lvl or "?") .. "|r", 1, 0.82, 0, 1, 1, 1)
    tip:AddDoubleLine("   " .. (zone or "zone unknown"), state, 0.75, 0.75, 0.75, sr, sg, sb)
    added = true
  end
  local seen = {}
  for _, q in ipairs(live[key] or {}) do
    seen[q.title] = true
    local state = q.done and "in your log: done" or (q.need and string.format("in your log: %d/%d", q.have or 0, q.need) or "in your log")
    questLine(q.title, q.level, q.zone, state, 0.4, 1, 0.4)
  end
  for title, e in pairs(C.db and C.db.questItems and C.db.questItems[key] or {}) do
    if not seen[title] then questLine(title, e.lvl, e.zone, "not in your quest log", 0.6, 0.6, 0.6) end
  end
  if not added then
    local qid, active = starter(id)
    if qid then
      local title = C_QuestLog and C_QuestLog.GetQuestInfo and C_QuestLog.GetQuestInfo(qid) or ("quest " .. qid)
      tip:AddDoubleLine("Starts a quest: |cffffffff" .. tostring(title) .. "|r", active and "in your log" or "not taken yet",
        1, 0.82, 0, active and 0.4 or 0.6, active and 1 or 0.6, active and 0.4 or 0.6)
      added = true
    end
  end
  return added
end

if CreateFrame then
  local f = CreateFrame("Frame")
  f:RegisterEvent("QUEST_LOG_UPDATE")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  local pendingScan = false
  f:SetScript("OnEvent", function()
    if pendingScan or not C.db then return end
    pendingScan = true
    local function go() pendingScan = false; pcall(Q.Scan) end
    if C.After then C.After(0.5, go) else go() end
  end)
end
