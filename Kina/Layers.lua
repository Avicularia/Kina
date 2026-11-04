-- Kina: window layering.
-- Kina windows open on top. Click another addon's window (ForeverForge, bags, ...)
-- and Kina steps back so that window is on top; click any Kina window and it comes
-- back to the front. Clicking the game world changes nothing.
local _, C = ...
-- BACK is LOW so nothing of Kina's (title bar, X button) can sit above a window
-- you clicked; children are set too, in case a template gave one its own layer.
local TOP, BACK = "FULLSCREEN_DIALOG", "LOW"
local function setStrata(f, strata, depth)
  f:SetFrameStrata(strata)
  if depth < 4 and f.GetChildren then
    for _, ch in ipairs({ f:GetChildren() }) do
      if not (ch.GetName and ch:GetName() == "KinaMenu") then setStrata(ch, strata, depth + 1) end
    end
  end
end
-- The farm widget is a HUD: it stays on its own layer and is never raised or lowered.
local NAMES = { "KinaFrame", "KinaDetail", "KinaMenu" }
local onTop = true

local function frames()
  local list = {}
  for _, n in ipairs(NAMES) do local f = _G[n]; if f then list[#list + 1] = f end end
  return list
end

-- Is this frame (or one of its parents) a Kina window?
local function isKina(f)
  local mine = {}
  for _, k in ipairs(frames()) do mine[k] = true end
  local depth = 0
  while f and depth < 30 do
    if mine[f] then return true end
    f = f.GetParent and f:GetParent() or nil
    depth = depth + 1
  end
  return false
end

function C.RaiseKina()
  onTop = true
  for _, f in ipairs(frames()) do
    -- the detail panel and menus stay above the main window
    local strata = (f:GetName() == "KinaMenu") and "TOOLTIP" or TOP
    setStrata(f, strata, 0)
    if f.Raise then f:Raise() end
  end
  local d = _G.KinaDetail
  if d and d:IsShown() and d.Raise then d:Raise() end
end

function C.LowerKina()
  onTop = false
  for _, f in ipairs(frames()) do
    if f:GetName() ~= "KinaMenu" then setStrata(f, BACK, 0) end
  end
end

local function focus()
  if GetMouseFoci then local t = GetMouseFoci(); return t and t[1] end
  if GetMouseFocus then return GetMouseFocus() end
end

-- Bringing Kina forward waits for the mouse button to come up: changing a window's
-- layer while it is being dragged makes it jump away from the cursor.
local pendingRaise = false
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GLOBAL_MOUSE_DOWN")
pcall(ev.RegisterEvent, ev, "GLOBAL_MOUSE_UP")
ev:SetScript("OnEvent", function(_, event)
  if not C.ready then return end
  if event == "GLOBAL_MOUSE_UP" then
    if pendingRaise and not C.dragging then pendingRaise = false; C.RaiseKina() end
    return
  end
  local f = focus()
  if not f or f == WorldFrame then return end -- clicking the world: leave layers alone
  if isKina(f) then
    if not onTop then pendingRaise = true end
  elseif onTop and not C.dragging then
    C.LowerKina()
  end
end)
