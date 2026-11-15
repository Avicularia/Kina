-- Kina: its own dialog box.
-- 1.0.4 (Taylor's taint log: "Execution tainted by Kina while reading field heightPadding
-- ... StaticPopup1:GetHeightPadding()" -> "An action was blocked because of taint from
-- Kina - SpellStopCasting()" on Escape): showing Kina's questions in the game's own popup
-- (StaticPopup1) left that popup tainted, and the next time the game closed windows on
-- Escape, it blocked its own actions and blamed Kina. Kina now draws every question in
-- its own frame and never calls the game's popup functions.
-- The question definitions keep their old shape (text, button1-3, OnAccept, OnCancel,
-- OnAlt, OnShow, hasEditBox ...) in Kina's own table C.Dialogs (older ones still read from
-- StaticPopupDialogs by name, which only reads it).
local _, C = ...
C.Dialogs = C.Dialogs or {}
local pool, live = {}, {}

local function info(which)
  return C.Dialogs[which]
end

local function build(i)
  local f = CreateFrame("Frame", "KinaDialog" .. i, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(420, 140); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
  f:SetPoint("TOP", UIParent, "TOP", 0, -135 - (i - 1) * 150)
  f:EnableMouse(true); f:SetClampedToScreen(true)
  local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.035, 0.03, 0.96)
  for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = f:CreateTexture(nil, "BORDER"); t:SetColorTexture(0.70, 0.50, 0.16, 1)
    t:SetPoint(p[1]); t:SetPoint(p[2]); if p[3] then t:SetHeight(2) else t:SetWidth(2) end
  end
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.text:SetPoint("TOP", 0, -18); f.text:SetWidth(380); f.text:SetJustifyH("CENTER")
  if f.text.SetWordWrap then f.text:SetWordWrap(true) end
  f.editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.editBox:SetSize(260, 22); f.editBox:SetAutoFocus(false); f.editBox:Hide()
  f.EditBox = f.editBox
  f.buttons = {}
  for b = 1, 3 do
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(128, 24)
    if C.Skin and C.Skin.Button then pcall(C.Skin.Button, btn) end
    btn:SetScript("OnClick", function() C._DialogClick(f, b) end)
    f.buttons[b] = btn
    f["button" .. b] = btn
  end
  f:SetScript("OnHide", function(self)
    local d = self.def
    live[self.which or ""] = nil
    if self.timer then self.timer = nil end
    -- closed with Escape: a "No" only for questions that allow it (hideOnEscape); the
    -- others (a dispute, a payment) just close and will be asked again
    if d and not self.answered and self.which then
      self.answered = true
      if d.OnCancel and d.hideOnEscape then pcall(d.OnCancel, self, self.data, "override") end
    end
    if d and d.OnHide then pcall(d.OnHide, self, self.data) end
  end)
  f:SetScript("OnUpdate", function(self, el)
    if self.timeout and self.timeout > 0 then
      self.timeout = self.timeout - el
      if self.timeout <= 0 then
        self.answered = true
        local d = self.def
        self:Hide()
        if d and d.OnCancel then pcall(d.OnCancel, self, self.data, "timeout") end
      end
    end
  end)
  -- Escape closes it (Kina's own frame in the list of windows Escape closes)
  if UISpecialFrames then table.insert(UISpecialFrames, f:GetName()) end
  f:Hide()
  return f
end

function C._DialogClick(f, b)
  local d = f.def
  if not d then f:Hide(); return end
  local keep
  f.answered = true
  if b == 1 and d.OnAccept then local ok, r = pcall(d.OnAccept, f, f.data, f.data2); keep = ok and r
  elseif b == 2 and d.OnCancel then pcall(d.OnCancel, f, f.data, "clicked")
  elseif b == 3 and d.OnAlt then pcall(d.OnAlt, f, f.data) end
  if keep then f.answered = false; return end
  f:Hide()
end

local function layout(f, d)
  local n = 0
  for b = 1, 3 do
    local label = d["button" .. b]
    local btn = f.buttons[b]
    if label then n = n + 1; btn:SetText(label); btn:Show() else btn:Hide() end
  end
  local th = f.text:GetStringHeight() or 14
  local h = 18 + th + 14
  if d.hasEditBox then
    f.editBox:ClearAllPoints(); f.editBox:SetPoint("TOP", f.text, "BOTTOM", 0, -10)
    f.editBox:SetWidth(d.editBoxWidth or 260); h = h + 34
  end
  local w = 136
  local x0 = -((n - 1) * w) / 2
  local k = 0
  for b = 1, 3 do
    local btn = f.buttons[b]
    if btn:IsShown() then
      btn:ClearAllPoints(); btn:SetPoint("BOTTOM", f, "BOTTOM", x0 + k * w, 14); k = k + 1
    end
  end
  f:SetHeight(h + 44)
  f:SetWidth(math.max(420, n * w + 30))
end

function C.ShowPopup(which, text1, text2, data, data2)
  -- 0.9.8: Kina steps back so its question isn't hidden behind the Kina window
  if C.LowerKina then pcall(C.LowerKina) end
  -- the test world counts popups through the game's stub
  if KINA_SIM_POPUPS and StaticPopup_Show then return StaticPopup_Show(which, text1, text2, data) end
  local d = info(which)
  if not d then return nil end
  -- one at a time per question: showing it again refreshes it
  local f = live[which]
  if not f then
    for i = 1, 4 do
      pool[i] = pool[i] or build(i)
      if not pool[i]:IsShown() then f = pool[i]; break end
    end
    f = f or pool[1]
  end
  f.def, f.which, f.data, f.data2, f.answered = d, which, data, data2, false
  local ok, txt = pcall(string.format, d.text or "%s", text1 or "", text2 or "")
  f.text:SetText(ok and txt or tostring(d.text or ""))
  if d.hasEditBox then
    f.editBox:Show(); f.editBox:SetText("")
    if d.maxLetters then f.editBox:SetMaxLetters(d.maxLetters) end
    f.editBox:SetScript("OnEnterPressed", function(e) if d.EditBoxOnEnterPressed then pcall(d.EditBoxOnEnterPressed, e, f.data) else C._DialogClick(f, 1) end end)
    f.editBox:SetScript("OnEscapePressed", function(e) if d.EditBoxOnEscapePressed then pcall(d.EditBoxOnEscapePressed, e, f.data) else f:Hide() end end)
    f.editBox:SetScript("OnTextChanged", function(e, user) if d.EditBoxOnTextChanged then pcall(d.EditBoxOnTextChanged, e, f.data) end end)
  else f.editBox:Hide() end
  f.timeout = (d.timeout and d.timeout > 0) and d.timeout or nil
  live[which] = f
  f:Show(); f:Raise()
  layout(f, d)
  if d.OnShow then pcall(d.OnShow, f, data) end
  if d.hasEditBox and d.autoFocus ~= false then f.editBox:SetFocus() end
  return f
end

function C.HidePopup(which)
  if KINA_SIM_POPUPS and StaticPopup_Hide then return StaticPopup_Hide(which) end
  local f = live[which]
  if f then f.answered = true; f:Hide() end
end
function C.PopupShown(which) return live[which] ~= nil end
