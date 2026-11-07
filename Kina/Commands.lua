-- Kina: slash commands and profession capture.
local _, C = ...

-- "1g20s5c", "35s", "250" (copper) -> copper
function C.ParseMoney(s)
  if not s then return nil end
  s = s:lower()
  if s:match("^%d+$") then return tonumber(s) end
  local g = tonumber(s:match("(%d+)g")) or 0
  local sv = tonumber(s:match("(%d+)s")) or 0
  local c = tonumber(s:match("(%d+)c")) or 0
  local total = g * 10000 + sv * 100 + c
  return total > 0 and total or nil
end

local function readProfessions()
  local prof = {}
  if GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ GetProfessions() }) do
      if idx then
        local name, _, rank = GetProfessionInfo(idx)
        if name then prof[name] = rank end
      end
    end
  end
  if next(prof) == nil and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank = GetSkillLineInfo(i)
      if name and not header and rank then prof[name] = rank end
    end
  end
  if next(prof) then C.char.prof = prof end
  -- Lockpicking is a skill line, not a profession
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if name and not header and name:lower():find("lockpick", 1, true) then
        C.char.lockpicking = rank; C.char.lockpickingMax = maxRank
      end
    end
  end
  C.char.level = UnitLevel and UnitLevel("player")
  C.char.class = UnitClass and select(2, UnitClass("player"))
end
C.On("PLAYER_LOGIN", readProfessions)
C.On("SKILL_LINES_CHANGED", readProfessions)
C.On("PLAYER_LEVEL_UP", readProfessions)

local help = {
  "/kina - open or close the window",
  "/kina bags | farms | deals | vendor | crafts | favor | track | ledger | session - open a tab",
  "/kina track [item link or id] - track or untrack an item",
  "/kina auto - open or don't open with the auction house",
  "/kina scan - full AH scan (shares the 15-minute limit with other scanners)",
  "/kina start [label] | stop - farming session",
  "/kina stock add [item link or id] [buy under] [sell at] - e.g. /kina stock add 249428 6s 90s",
  "/kina stock del [item link or id]",
  "/kina kph [number] - default kills per hour for farm ranking",
  "/kina hud - show or hide the farm widget (drag it anywhere)",
  "/kina sound - farm start/stop fanfares on or off",
  "/kina timer [hours] - farm timer, 0 = none (e.g. /kina timer 2)",
  "/kina autoscan - full AH scan when the auction house opens, on or off",
  "/kina tooltip - vendor, auction and disenchant prices on item tooltips, on or off",
  "/kina defriend [skill | off] - count disenchanting as an option when a friend with that Enchanting skill does it for you",
  "/kina minprofit [amount | auto] - the least a trade must make to be worth your time (auto = 2 min of your gold/hour)",
  "/kina roi [percent] - hide rows under this ROI on every tab (same as the Min ROI box)",
  "/kina share [on | off | guild | now | verbose | forget] - pool AH, loot and vendor data with other Kina users in your group",
  "/kina reset - put every Kina window back in its default place",
  "/kina forgive [name] - forgive what someone owes you (the oldest debt first)",
  "/kina pp - pickpocketing (badges, pocket data, sharing): /kina pp help for more",
  "/kina pph [number] - picks per hour used for pick-only estimates",
}

SLASH_KINA1 = "/kina"
SLASH_KINA2 = "/ksc" -- old name, still works
SlashCmdList.KINA = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then C.Toggle()
  elseif (cmd == "bags" or cmd == "farms" or cmd == "deals" or cmd == "vendor" or cmd == "crafts" or cmd == "favor"
      or cmd == "track" or cmd == "ledger" or cmd == "session") and rest == "" then
    C.Toggle(cmd:sub(1, 1):upper() .. cmd:sub(2))
  elseif cmd == "stock" and rest == "" then C.Toggle("Track")
  elseif cmd == "track" then
    local id = C.ItemIDFromLink(rest) or tonumber(rest)
    if id then C.ToggleTrack(id); C.Refresh() end
  elseif cmd == "auto" then
    C.settings.autoOpen = (C.settings.autoOpen == false)
    C.Print("open with the auction house: " .. (C.settings.autoOpen and "on" or "off"))
  elseif cmd == "scan" then C.StartScanLoop()
  elseif cmd == "selftest" or cmd == "test" then if C.SelfTest then C.SelfTest.Run() end
  elseif cmd == "forgive" then
    local want = rest ~= "" and rest:lower() or nil
    local hit
    for _, d in ipairs(C.Debts()) do
      if d.dir == "owed" and not d.topup and (not want or tostring(d.who):lower():find(want, 1, true) == 1) then hit = d; break end
    end
    if hit then C.Forgive(hit) else C.Print(want and ("nobody called " .. rest .. " owes you anything.") or "nobody owes you anything.") end
  elseif cmd == "start" then C.StartSession(rest ~= "" and rest or nil)
  elseif cmd == "stop" then C.StopSession()
  elseif cmd == "kph" then
    local n = tonumber(rest); if n and n > 0 then C.settings.killsPerHour = n; C.Print("default kills/hour = " .. n) end
  elseif cmd == "hud" or cmd == "widget" then C.ShowWidget(not C.settings.hudShown)
  elseif cmd == "profile" then
    local who = rest ~= "" and rest or (UnitName and UnitName("target"))
    if C.Profile then C.Profile.Show(who) end
  elseif cmd == "pardon" then if C.Rules then C.Rules.OfferPardon() end
  elseif cmd == "vouch" then
    C.Print("commendations happen in the window that opens when a group farm ends.")
  elseif cmd == "preview" and rest == "commend" then if C.Vouch then C.Vouch.ShowPrompt(true) end
  elseif cmd == "preview" then if C.Toast and C.Toast.Preview then C.Toast.Preview(rest) end
  elseif cmd == "sound" then
    if C.SetVolume then C.SetVolume(C.Volume() > 0 and 0 or 4) else C.settings.farmSound = (C.settings.farmSound == false) end
    C.Print("farm fanfares: " .. (C.settings.farmSound and "on" or "off"))
    if C.settings.farmSound then C.PlayClick() end
    if C.RefreshWidget then C.RefreshWidget() end
  elseif cmd == "timer" then
    local h = tonumber(rest)
    if h and h >= 0 then C.settings.farmPreset = math.floor(h * 3600); C.Print("farm timer: " .. (h > 0 and (h .. "h") or "none")) end
    if C.RefreshWidget then C.RefreshWidget() end
  elseif cmd == "autoscan" then
    C.settings.autoScan = (C.settings.autoScan == false)
    C.Print("keep scanning every 15 min after you click Scan: " .. (C.settings.autoScan and "on" or "off"))
  elseif cmd == "tooltip" or cmd == "tip" then C.ToggleTooltip()
  elseif cmd == "defriend" then
    local n = tonumber(rest)
    if rest == "off" then C.settings.deFriend = nil elseif n then C.settings.deFriend = n end
    C.Print("disenchanter available: " .. (C.DisenchantSkill() and ("Enchanting " .. C.DisenchantSkill()) or "none (disenchant routes hidden)"))
    C.Refresh()
  elseif cmd == "minprofit" then
    if rest == "auto" or rest == "" then C.settings.minProfit = nil else C.settings.minProfit = C.ParseMoney(rest) or (rest == "0" and 0) or C.settings.minProfit end
    C.Print("a trade must clear " .. C.Money(C.Econ.Overhead()) .. (C.settings.minProfit and "" or " (auto: 2 minutes of your gold/hour)"))
    C.Refresh()
  elseif cmd == "roi" then
    C.settings.minROI = tonumber(rest) or 0
    if _G.KinaMinROI then _G.KinaMinROI:SetText(tostring(C.settings.minROI)) end
    C.Print("minimum ROI shown: " .. C.settings.minROI .. "%"); C.Refresh()
  elseif cmd == "share" or cmd == "sync" then C.Share.Command(rest)
  elseif cmd == "reset" then C.ResetWindows()
  elseif cmd == "pp" or cmd == "pockets" then C.Pockets.Command(rest)
  elseif cmd == "pph" then
    local n = tonumber(rest); if n and n > 0 then C.settings.picksPerHour = n; C.Print("picks per hour = " .. n) end
  elseif cmd == "debug" then C.debug = not C.debug; C.Print("debug " .. tostring(C.debug))
  elseif cmd == "stock" then
    local sub, args = rest:match("^(%S+)%s*(.-)$")
    local id = args and (C.ItemIDFromLink(args) or tonumber(args:match("^(%d+)")))
    if sub == "add" and id then
      local after = args:gsub("|c.-|r", ""):gsub("^%d+", "")
      local buy, sell = after:match("(%S+)%s+(%S+)")
      C.db.stock[id] = { buyUnder = C.ParseMoney(buy), sellAt = C.ParseMoney(sell), note = "", added = C.Now() }
      if C.db.stockRemoved then C.db.stockRemoved[id] = nil end
      C.Print("stockpile: added item " .. id)
    elseif sub == "del" and id then
      C.db.stock[id] = nil
      C.db.stockRemoved = C.db.stockRemoved or {}; C.db.stockRemoved[id] = true
      C.Print("stockpile: removed item " .. id)
    else C.Print("usage: /kina stock add [item] [buy under] [sell at]") end
    C.Refresh()
  else
    for _, line in ipairs(help) do C.Print(line) end
  end
end
