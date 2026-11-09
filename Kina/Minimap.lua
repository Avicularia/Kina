-- Kina: the round button on the edge of the minimap.
-- Left-click: Kina window. Right-click: farm widget. Drag it around the minimap.
local _, C = ...
local ICON = "Interface\\AddOns\\Kina\\Media\\KinaLogo"
local b

local function place()
  if not b then return end
  local a = math.rad(C.settings.minimapAngle or 215)
  local r = (Minimap:GetWidth() / 2) + 5
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function build()
  if b or not Minimap then return end
  b = CreateFrame("Button", "KinaMinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20); bg:SetPoint("CENTER", 0, 1)
  local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetTexture(ICON); icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
  local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then C.ShowWidget(not (C.settings.hudShown ~= false)) else C.Toggle() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Kina " .. (C.version or ""), 0.31, 0.76, 0.97)
    GameTooltip:AddLine("Left-click: open or close Kina", 1, 1, 1)
    GameTooltip:AddLine("Right-click: show or hide the farm widget", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button around the map", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self)
    C.GuardScript(self, "OnUpdate", "Minimap:39", function()
      local mx, my = Minimap:GetCenter()
      local s = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      C.settings.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  place()
end

function C.ShowMinimapButton(show)
  C.settings.minimapHide = not show
  if show then build(); if b then b:Show() end elseif b then b:Hide() end
end
C.On("PLAYER_LOGIN", function() if not C.settings.minimapHide then build() end end)
