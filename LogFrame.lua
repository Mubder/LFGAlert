-- LFGAlert - LogFrame.lua
-- Scrollable applicant log with right-click whisper/invite.
local ADDON_NAME = ...
LFGAlert = LFGAlert or {}
local NS = LFGAlert

local ROW_HEIGHT = 22
local PAGE_SIZE = 15 -- rows per page; fits the list area exactly
NS.logPage = NS.logPage or 1 -- 1 = newest entries

local logFrame, listContainer, rows = nil, nil, {}
local countLabel
local prevBtn, nextBtn

local function ClassColorize(classFileName, text)
  if classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName] then
    local c = RAID_CLASS_COLORS[classFileName]
    if c.WrapTextInColorCode then
      return c:WrapTextInColorCode(text)
    elseif c.colorStr then
      return "|c" .. c.colorStr .. text .. "|r"
    end
  end
  return text
end

local function ShortName(fullName)
  if not fullName then return "?" end
  local bare = strsplit("-", fullName, 2)
  return bare or fullName
end

local function TimeStr(t)
  if not t then return "--:--" end
  return date("%H:%M:%S", t)
end

-- ---------------------------------------------------------------------------
-- Table columns. ONE definition drives both the header labels and every row,
-- so values always sit exactly under their heading. Numeric columns are
-- right-aligned; text is truncated (UTF-8 safe) so it can never bleed over.
-- ---------------------------------------------------------------------------

local FRAME_W, FRAME_H = 860, 480
local ROW_GAP = 6
local ACTW = 72 -- action-button zone at each row's right edge (3 x 20px)

local COLS = {
  { key = "time",   label = "Time",       width = 56,  justify = "LEFT" },
  { key = "name",   label = "Applicant",  width = 112, justify = "LEFT" },
  { key = "role",   label = "Role",       width = 58,  justify = "LEFT" },
  { key = "spec",   label = "Class/Spec", width = 92,  justify = "LEFT" },
  { key = "run",    label = "Key",        width = 58,  justify = "LEFT" },
  { key = "ilvl",   label = "iLvl",       width = 46,  justify = "RIGHT" },
  { key = "score",  label = "M+ Score",   width = 52,  justify = "RIGHT" },
  { key = "status", label = "Status",     width = 112, justify = "LEFT" },
  { key = "note",   label = "Notes",      width = 0,   justify = "LEFT" }, -- fills remainder before actions
}

-- Byte-safe truncation that never splits a UTF-8 sequence.
local function Trunc(s, n)
  if not s or s == "" then return "" end
  if #s <= n then return s end
  local cut = s:sub(1, n - 1)
  cut = cut:gsub("[\194-\244][\128-\191]*$", "")
  return cut .. "…"
end

-- ---------------------------------------------------------------------------
-- Filter + search (status filter + text search over name/spec/class/note)
-- ---------------------------------------------------------------------------

NS.logFilter = NS.logFilter or { status = "ALL", query = "" }
NS.logFilter.class = NS.logFilter.class or "ALL"
NS.logFilter.minKey = NS.logFilter.minKey or 0

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
  "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }

local function ClassLabel(classFile)
  if classFile == "ALL" then return "All Classes" end
  local loc = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
  return ClassColorize(classFile, loc or (classFile or "?"):lower():gsub("^%l", string.upper))
end

local KEY_OPTIONS = { 0, 2, 5, 10, 15, 20 }

local function KeyLabel(minKey)
  if not minKey or minKey <= 0 then return "All" end
  return "+" .. tostring(minKey) .. "+"
end

function NS.SetLogClassFilter(class)
  local c = (class or "ALL"):upper():gsub("%s+", "")
  if c ~= "ALL" and not (RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]) then c = "ALL" end
  NS.logFilter.class = c
  if NS.RefreshLogUI then NS.RefreshLogUI() end
  return c
end

function NS.SetLogMinKey(n)
  n = math.max(0, math.floor(tonumber(n) or 0))
  NS.logFilter.minKey = n
  if NS.RefreshLogUI then NS.RefreshLogUI() end
  return n
end

-- Filter keys shown in the dropdown. Several raw statuses collapse into one key.
local FILTER_OPTIONS = {
  { key = "ALL",      label = "All" },
  { key = "QUEUED",   label = "Queued" },
  { key = "INVITED",  label = "Invited" },
  { key = "ACCEPTED", label = "Accepted" },
  { key = "DECLINED", label = "Declined" },
  { key = "GONE",     label = "Cancelled / Timeout" },
}

local DECLINED_SET = {
  declined = true, declined_full = true, declined_delisted = true,
  invitedeclined = true, failed = true,
}

local function FilterKeyForStatus(status)
  if status == "applied" then return "QUEUED" end
  if status == "invited" then return "INVITED" end
  if status == "inviteaccepted" then return "ACCEPTED" end
  if DECLINED_SET[status] then return "DECLINED" end
  if status == "cancelled" or status == "timedout" then return "GONE" end
  return "OTHER"
end

local function FilterLabel(key)
  for _, o in ipairs(FILTER_OPTIONS) do
    if o.key == key then return o.label end
  end
  return key or "All"
end

function NS.SetLogFilter(status)
  local s = (status or "ALL"):upper()
  if s == "QUEUE" then s = "QUEUED" end
  local valid = false
  for _, o in ipairs(FILTER_OPTIONS) do
    if o.key == s then valid = true break end
  end
  NS.logFilter.status = valid and s or "ALL"
  if NS.RefreshLogUI then NS.RefreshLogUI() end
  return NS.logFilter.status
end

function NS.SetLogSearch(q)
  NS.logFilter.query = (q or ""):lower()
  if NS.RefreshLogUI then NS.RefreshLogUI() end
end

local function EntryMatches(entry)
  local f = NS.logFilter
  if entry.separator then
    -- Separators only make sense in the unfiltered view.
    return f.status == "ALL" and (f.class or "ALL") == "ALL"
      and (f.minKey or 0) <= 0 and (f.query == nil or f.query == "")
  end
  if f.status ~= "ALL" and FilterKeyForStatus(entry.status) ~= f.status then
    return false
  end
  local cf = f.class or "ALL"
  if cf ~= "ALL" then
    local m0 = entry.members and entry.members[1]
    if not (m0 and m0.class == cf) then return false end
  end
  local mk = f.minKey or 0
  if mk > 0 and not (entry.key and entry.key >= mk) then
    return false
  end
  local q = f.query
  if q and q ~= "" then
    local m = entry.members and entry.members[1]
    local hay = {}
    if m then
      hay[#hay + 1] = m.name or ""
      hay[#hay + 1] = m.specName or ""
      hay[#hay + 1] = m.class or ""
      hay[#hay + 1] = m.localizedClass or ""
      if NS.ResolveRole and NS.RoleTag then
        local _, rolePlain = NS.RoleTag(NS.ResolveRole(m))
        hay[#hay + 1] = rolePlain or ""
        hay[#hay + 1] = NS.ResolveRole(m) or ""
      end
    end
    hay[#hay + 1] = entry.comment or ""
    hay[#hay + 1] = entry.status or ""
    hay[#hay + 1] = entry.dungeon or ""
    hay[#hay + 1] = entry.dungeonFull or ""
    local label = NS.StatusLabel and select(1, NS.StatusLabel(entry.status)) or ""
    hay[#hay + 1] = label or ""
    local blob = table.concat(hay, " "):lower()
    if not blob:find(q, 1, true) then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Context menu (right-click a row)
-- ---------------------------------------------------------------------------

local function ShowRowMenu(anchor, entry)
  if not entry or not entry.members or not entry.members[1] then return end
  local mem = entry.members[1]
  local fullName = mem.name
  local applicantID = entry.applicantID

  -- Modern MenuUtil (Dragonflight+) path
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle(ShortName(fullName))
      root:CreateButton("Whisper", function()
        NS.Whisper(fullName)
      end)
      root:CreateButton("Invite to group", function()
        if applicantID and applicantID ~= 0 then
          NS.InviteApplicantByID(applicantID)
        end
        NS.InviteByName(fullName)
      end)
      if applicantID and applicantID ~= 0 then
        root:CreateButton("Accept applicant (LFG invite)", function()
          NS.InviteApplicantByID(applicantID)
        end)
        root:CreateButton("Decline applicant", function()
          NS.DeclineApplicantByID(applicantID)
        end)
      end
      root:CreateDivider()
      root:CreateButton("Copy name", function()
        local eb = ChatEdit_ChooseBoxForSend()
        if eb then
          eb:Show()
          eb:SetText(fullName)
          eb:HighlightText()
        end
      end)
    end)
    return
  end

  -- Fallback: classic dropdown
  if not LFGAlertDropMenu then
    CreateFrame("Frame", "LFGAlertDropMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local menu = {
    { text = ShortName(fullName), isTitle = true, notCheckable = true },
    { text = "Whisper", notCheckable = true, func = function() NS.Whisper(fullName) end },
    { text = "Invite to group", notCheckable = true, func = function()
        if applicantID and applicantID ~= 0 then NS.InviteApplicantByID(applicantID) end
        NS.InviteByName(fullName)
      end },
  }
  if applicantID and applicantID ~= 0 then
    menu[#menu + 1] = { text = "Decline applicant", notCheckable = true, func = function() NS.DeclineApplicantByID(applicantID) end }
  end
  EasyMenu(menu, LFGAlertDropMenu, "cursor", 0, 0, "MENU")
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function MakeRow(parent, idx)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(ROW_HEIGHT)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -(idx - 1) * ROW_HEIGHT - 4)
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -(idx - 1) * ROW_HEIGHT - 4)

  -- Row background: tinted per status on every refresh (see StatusTint).
  local stripe = b:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints()
  stripe:SetColorTexture(0.5, 0.38, 0.12, 0.2)
  b.stripe = stripe

  -- One FontString per column, laid out from the same COLS spec as the header.
  -- The note column stops before the action-button zone at the right edge.
  b.cols = {}
  local x = 2
  for _, c in ipairs(COLS) do
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH(c.justify)
    fs:SetWordWrap(false)
    if c.key == "note" then
      fs:SetPoint("LEFT", b, "LEFT", x, 0)
      fs:SetPoint("RIGHT", b, "RIGHT", -(2 + ACTW + ROW_GAP), 0)
    else
      fs:SetPoint("LEFT", b, "LEFT", x, 0)
      fs:SetWidth(c.width)
      x = x + c.width + ROW_GAP
    end
    b.cols[c.key] = fs
  end

  -- One-click action buttons (whisper / invite / decline), right edge.
  b.act = {}
  local actDefs = {
    { icon = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", tip = "Whisper" },
    { icon = "Interface\\RaidFrame\\ReadyCheck-Ready", tip = "Invite to group" },
    { icon = "Interface\\RaidFrame\\ReadyCheck-NotReady", tip = "Decline applicant" },
  }
  for i, a in ipairs(actDefs) do
    local ab = CreateFrame("Button", nil, b)
    ab:SetSize(20, 20)
    ab:SetPoint("RIGHT", b, "RIGHT", -2 - (3 - i) * 24, 0)
    ab:SetNormalTexture(a.icon)
    ab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ab:SetScript("OnClick", function()
      local e = b.entry
      if not e or e.separator or not e.members or not e.members[1] then return end
      local fullName, applicantID = e.members[1].name, e.applicantID
      if i == 1 then
        NS.Whisper(fullName)
      elseif i == 2 then
        if applicantID and applicantID ~= 0 then NS.InviteApplicantByID(applicantID) end
        NS.InviteByName(fullName)
      elseif applicantID and applicantID ~= 0 then
        NS.DeclineApplicantByID(applicantID)
      end
    end)
    ab:SetScript("OnEnter", function(self)
      local e = b.entry
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if e and not e.separator and e.members and e.members[1] then
        GameTooltip:SetText(a.tip .. ": " .. ShortName(e.members[1].name), 1, 1, 1)
      else
        GameTooltip:SetText(a.tip, 1, 1, 1)
      end
      GameTooltip:Show()
    end)
    ab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.act[i] = ab
  end

  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" and self.entry then
      ShowRowMenu(self, self.entry)
    elseif self.entry and self.entry.members and self.entry.members[1] then
      NS.Whisper(self.entry.members[1].name)
    end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local e = self.entry
    if e.separator then
      GameTooltip:SetText(e.separator)
      GameTooltip:Show()
      return
    end
    local m = e.members and e.members[1]
    if not m then return end
    GameTooltip:SetText(ShortName(m.name), 1, 1, 1)
    if m.class then
      local line = (m.specName and (m.specName .. " ") or "") .. (m.class or "")
      GameTooltip:AddLine(line, 1, 0.82, 0)
    end
    if NS.ResolveRole and NS.RoleTag then
      local roleTag = NS.RoleTag(NS.ResolveRole(m))
      GameTooltip:AddDoubleLine("Role", roleTag, 1, 1, 1, 1, 1, 1)
    end
    if e.dungeon or e.key then
      local runLine = (e.key and ("+" .. e.key .. " ") or "") .. (e.dungeonFull or e.dungeon or "")
      if e.keySource == "keystone" then runLine = runLine .. "  |cffaaaaaa(your key)|r" end
      GameTooltip:AddDoubleLine("Run", runLine, 1, 1, 1, 1, 0.82, 0)
    end
    if e.listingTitle and e.listingTitle ~= "" then
      GameTooltip:AddDoubleLine("Listing", e.listingTitle, 1, 1, 1, 0.8, 0.8, 0.8)
    end
    GameTooltip:AddDoubleLine("Item level", tostring(m.itemLevel or "-"), 1,1,1, 1,1,1)
    local blizz = (m.dungeonScore and m.dungeonScore > 0) and tostring(m.dungeonScore) or "-"
    local rio = (m.rioScore and m.rioScore > 0) and tostring(m.rioScore) or "-"
    GameTooltip:AddDoubleLine("M+ rating (Blizzard)", blizz, 1,1,1, 1,1,1)
    GameTooltip:AddDoubleLine("RIO score" .. (_G.RaiderIO and "" or " (install Raider.IO)"), rio, 1,1,1, 1,1,1)
    if (e.numMembers or 1) > 1 and e.members then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Group application (" .. e.numMembers .. "):", 0.9, 0.9, 0.9)
      for i = 2, math.min(#e.members, 8) do
        local o = e.members[i]
        GameTooltip:AddDoubleLine(ShortName(o.name), (o.specName or o.class or "") .. "  ilvl " .. tostring(o.itemLevel or "-") .. "  M+ " .. tostring((o.rioScore and o.rioScore > 0) and o.rioScore or (o.dungeonScore or "-")), 1,1,1, 0.9,0.9,0.9)
      end
    end
    if e.comment and e.comment ~= "" then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("\"" .. e.comment .. "\"", 0.7, 0.9, 1, true)
    end
    local label, _ = NS.StatusLabel(e.status)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Status: " .. label, 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: whisper / invite / decline", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- Row tint by status: green invited/accepted, red declined, gold queued, grey gone.
local function StatusTint(status)
  if status == "inviteaccepted" then return 0.15, 0.6, 0.2 end
  if status == "invited" then return 0.1, 0.45, 0.16 end
  if status == "applied" then return 0.5, 0.38, 0.12 end
  if status == "cancelled" or status == "timedout" then return 0.35, 0.35, 0.35 end
  return 0.55, 0.12, 0.12 -- declined-ish
end

-- Returns one string per COLS key so every value lands under its heading.
local function EntryColumns(entry)
  if entry.separator then return nil end
  local m = entry.members and entry.members[1]
  local label, color = NS.StatusLabel(entry.status)
  local cols = {}
  cols.time = TimeStr(entry.t)
  cols.status = "|cff" .. color .. label .. "|r"
  -- Run context is known even when member data isn't (e.g. fresh "?" rows).
  if entry.key and entry.dungeon then
    cols.run = "|cffffd100+" .. tostring(entry.key) .. " " .. Trunc(entry.dungeon, 5) .. "|r"
  elseif entry.key then
    cols.run = "|cffffd100+" .. tostring(entry.key) .. "|r"
  elseif entry.dungeon then
    cols.run = Trunc(entry.dungeon, 7)
  else
    cols.run = "-"
  end
  if not m then
    cols.name, cols.role, cols.spec, cols.ilvl, cols.score, cols.note = "?", "-", "-", "-", "-", ""
    return cols
  end
  local star = ""
  local ilvlTxt, scoreTxt
  local thrOn, meetsAll = false, false
  if NS.MeetsThresholds and NS.db and (NS.db.minIlvl > 0 or NS.db.minScore > 0) then
    thrOn = true
    local meetsIlvl, meetsScore, ma = NS.MeetsThresholds(m)
    meetsAll = ma and true or false
    local ilvlNum = (m.itemLevel and m.itemLevel > 0) and math.floor(m.itemLevel) or nil
    local scoreNum = NS.EffectiveScore and NS.EffectiveScore(m) or 0
    if ilvlNum then
      ilvlTxt = (meetsIlvl and "|cff33cc33" or "|cffff5555") .. tostring(ilvlNum) .. "|r"
    else
      ilvlTxt = "-"
    end
    if scoreNum and scoreNum > 0 then
      scoreTxt = (meetsScore and "|cff33cc33" or "|cffff5555") .. tostring(math.floor(scoreNum)) .. "|r"
    else
      scoreTxt = "-"
    end
    if meetsAll then star = "|cffffd100★ |r" end
  else
    ilvlTxt = (m.itemLevel and m.itemLevel > 0) and tostring(math.floor(m.itemLevel)) or "-"
    local scoreNum = (m.rioScore and m.rioScore > 0) and m.rioScore or (m.dungeonScore or 0)
    scoreTxt = (scoreNum and scoreNum > 0) and tostring(math.floor(scoreNum)) or "-"
  end
  local nameTxt = star .. ClassColorize(m.class, Trunc(ShortName(m.name), 20))
  if (entry.numMembers or 1) > 1 then
    nameTxt = nameTxt .. " |cffaaaaaa+" .. ((entry.numMembers or 1) - 1) .. "|r"
  end
  cols.name = nameTxt
  cols.role = NS.RoleTag(NS.ResolveRole(m))
  if entry.autoDeclined then
    cols.status = "|cffff5555Declined" .. (entry.declineReason and (" (" .. entry.declineReason .. ")") or " (Auto)") .. "|r"
  elseif entry.status == "applied" and thrOn and meetsAll then
    cols.status = "|cffffd100Queued ★|r"
  end
  cols.spec = Trunc(m.specName or m.localizedClass or m.class or "-", 14)
  cols.ilvl = ilvlTxt
  cols.score = scoreTxt
  cols.note = (entry.comment and entry.comment ~= "") and ("|cff88bbff" .. Trunc(entry.comment, 22) .. "|r") or ""
  return cols
end

local filterButton, searchBox, classBtn, keyBtn

local function RefreshFilterButton()
  if filterButton and filterButton.Text then
    filterButton.Text:SetText("Status: " .. FilterLabel(NS.logFilter.status))
  elseif filterButton then
    filterButton:SetText("Status: " .. FilterLabel(NS.logFilter.status))
  end
end

local function SetButtonLabel(btn, text)
  if not btn then return end
  if btn.Text then btn.Text:SetText(text) else btn:SetText(text) end
end

local function RefreshClassButton()
  local cf = NS.logFilter.class or "ALL"
  local label = cf == "ALL" and "All" or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf]) or cf
  SetButtonLabel(classBtn, "Class: " .. label)
end

local function RefreshKeyButton()
  SetButtonLabel(keyBtn, "Key: " .. KeyLabel(NS.logFilter.minKey))
end

local function ShowClassMenu(anchor)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle("Filter by class")
      root:CreateCheckbox("All Classes",
        function() return (NS.logFilter.class or "ALL") == "ALL" end,
        function() NS.SetLogClassFilter("ALL") RefreshClassButton() end)
      for _, classFile in ipairs(CLASS_ORDER) do
        local cf = classFile
        root:CreateCheckbox(ClassLabel(cf),
          function() return NS.logFilter.class == cf end,
          function() NS.SetLogClassFilter(cf) RefreshClassButton() end)
      end
    end)
    return
  end
  if not LFGAlertClassMenu then
    CreateFrame("Frame", "LFGAlertClassMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local menu = { { text = "Filter by class", isTitle = true, notCheckable = true },
    { text = "All Classes", checked = (NS.logFilter.class or "ALL") == "ALL",
      func = function() NS.SetLogClassFilter("ALL") RefreshClassButton() end } }
  for _, classFile in ipairs(CLASS_ORDER) do
    local cf = classFile
    menu[#menu + 1] = { text = ClassLabel(cf), checked = NS.logFilter.class == cf, notCheckable = false,
      func = function() NS.SetLogClassFilter(cf) RefreshClassButton() end }
  end
  EasyMenu(menu, LFGAlertClassMenu, "cursor", 0, 0, "MENU")
end

local function ShowKeyMenu(anchor)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle("Minimum key level")
      for _, kv in ipairs(KEY_OPTIONS) do
        local label = kv == 0 and "All Keys" or ("Minimum +" .. kv)
        root:CreateCheckbox(label,
          function() return (NS.logFilter.minKey or 0) == kv end,
          function() NS.SetLogMinKey(kv) RefreshKeyButton() end)
      end
    end)
    return
  end
  if not LFGAlertKeyMenu then
    CreateFrame("Frame", "LFGAlertKeyMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local menu = { { text = "Minimum key level", isTitle = true, notCheckable = true } }
  for _, kv in ipairs(KEY_OPTIONS) do
    local label = kv == 0 and "All Keys" or ("Minimum +" .. kv)
    menu[#menu + 1] = { text = label, checked = (NS.logFilter.minKey or 0) == kv, notCheckable = false,
      func = function() NS.SetLogMinKey(kv) RefreshKeyButton() end }
  end
  EasyMenu(menu, LFGAlertKeyMenu, "cursor", 0, 0, "MENU")
end

local function ShowFilterMenu(anchor)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle("Filter by status")
      for _, o in ipairs(FILTER_OPTIONS) do
        root:CreateCheckbox(o.label, function() return NS.logFilter.status == o.key end, function()
          NS.SetLogFilter(o.key)
          RefreshFilterButton()
        end)
      end
    end)
    return
  end
  if not LFGAlertFilterMenu then
    CreateFrame("Frame", "LFGAlertFilterMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local menu = { { text = "Filter by status", isTitle = true, notCheckable = true } }
  for _, o in ipairs(FILTER_OPTIONS) do
    menu[#menu + 1] = { text = o.label, checked = NS.logFilter.status == o.key, notCheckable = false,
      func = function() NS.SetLogFilter(o.key) RefreshFilterButton() end }
  end
  EasyMenu(menu, LFGAlertFilterMenu, "cursor", 0, 0, "MENU")
end

function NS.LogPageDelta(d)
  NS.logPage = (NS.logPage or 1) + (d or 0)
  NS.RefreshLogUI()
end

function NS.RefreshLogUI()
  if not logFrame or not listContainer then return end
  local log = (NS.db and NS.db.log) or {}
  -- Build filtered view first (oldest->newest), then display newest first.
  local view = {}
  for i = 1, #log do
    if EntryMatches(log[i]) then view[#view + 1] = log[i] end
  end
  local n = #view
  -- Paging (page 1 = newest). New arrivals jump back to page 1.
  if n > (NS._lastTotal or 0) then NS.logPage = 1 end
  NS._lastTotal = n
  local pages = math.max(1, math.ceil(n / PAGE_SIZE))
  NS.logPage = math.min(math.max(NS.logPage or 1, 1), pages)
  local skip = (NS.logPage - 1) * PAGE_SIZE -- newest entries skipped
  if countLabel then
    local total = #log
    local suffix = ""
    if NS.logFilter.status ~= "ALL" then suffix = suffix .. "  •  filter: " .. FilterLabel(NS.logFilter.status) end
    if (NS.logFilter.class or "ALL") ~= "ALL" then
      local cf = NS.logFilter.class
      suffix = suffix .. "  •  " .. ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf]) or cf)
    end
    if (NS.logFilter.minKey or 0) > 0 then suffix = suffix .. "  •  key " .. KeyLabel(NS.logFilter.minKey) end
    if NS.logFilter.query ~= "" then suffix = suffix .. "  •  search: \"" .. NS.logFilter.query .. "\"" end
    if NS.db and (NS.db.minIlvl > 0 or NS.db.minScore > 0) then
      suffix = suffix .. string.format("  •  ★ needs ilvl %s / M+ %s",
        NS.db.minIlvl > 0 and tostring(NS.db.minIlvl) or "-",
        NS.db.minScore > 0 and tostring(NS.db.minScore) or "-")
    end
    countLabel:SetText(n .. " of " .. total .. " entries" .. suffix .. string.format("  •  Page %d/%d", NS.logPage, pages))
  end
  if prevBtn then prevBtn:SetEnabled(NS.logPage > 1) end
  if nextBtn then nextBtn:SetEnabled(NS.logPage < pages) end
  RefreshFilterButton()
  RefreshClassButton()
  RefreshKeyButton()
  for i = 1, PAGE_SIZE do
    local row = rows[i]
    local entry = view[n - skip - i + 1]
    if not row then break end
    if entry then
      row:Show()
      row.entry = entry
      local tr, tg, tb, ta = 0.2, 0.2, 0.2, 0.12
      if not entry.separator then
        tr, tg, tb = StatusTint(entry.status)
        ta = 0.22
      end
      row.stripe:SetColorTexture(tr, tg, tb, ta)
      local hasID = entry.applicantID and entry.applicantID ~= 0 and true or false
      row.act[1]:SetShown(not entry.separator)
      row.act[2]:SetShown(not entry.separator)
      row.act[3]:SetShown(not entry.separator and hasID)
      if entry.separator then
        for _, c in ipairs(COLS) do
          row.cols[c.key]:SetText(c.key == "name" and entry.separator or "")
        end
      else
        local okR, vals = pcall(EntryColumns, entry)
        if okR and vals then
          for _, c in ipairs(COLS) do
            row.cols[c.key]:SetText(vals[c.key] or "")
          end
        else
          NS._lastRenderError = tostring(vals)
          for _, c in ipairs(COLS) do
            row.cols[c.key]:SetText(c.key == "name" and "|cffff5555Render error — /lfgalert debug|r" or "")
          end
        end
      end
    else
      row:Hide()
      row.entry = nil
    end
  end
  -- Empty state: say WHY it's empty (no data vs. filter hiding everything).
  if n == 0 and rows[1] then
    local r = rows[1]
    r:Show()
    r.entry = nil
    local hint = (#log == 0)
      and "No applicants logged yet — new queues will appear here"
      or "No match — set Filter: All and clear the search box"
    for _, c in ipairs(COLS) do
      r.cols[c.key]:SetText(c.key == "name" and ("|cffaaaaaa" .. hint .. "|r") or "")
    end
  end
end

-- Snapshot for /lfgalert debug.
function NS.GetLogUIState()
  local vis = 0
  for _, r in ipairs(rows) do
    if r:IsShown() then vis = vis + 1 end
  end
  return { built = logFrame ~= nil, shown = logFrame and logFrame:IsShown() or false, visibleRows = vis }
end

-- Live render probe for /lfgalert debug: row pool, first row state,
-- and a direct EntryColumns test on the newest stored entry.
function NS.ProbeLogUI()
  local p = { pool = #rows, built = NS._rowsBuilt or 0, page = NS.logPage or 1 }
  local r1 = rows[1]
  p.r1 = (r1 ~= nil)
  if r1 then
    p.shown = r1:IsShown()
    p.hasEntry = r1.entry ~= nil
    local empty = 0
    for _, c in ipairs(COLS) do
      local fs = r1.cols and r1.cols[c.key]
      local tx = fs and fs:GetText()
      if not tx or tx == "" then empty = empty + 1 end
    end
    p.emptyCols = empty
    local _, _, _, _, ry = r1:GetPoint(1)
    p.row1Y = ry and math.floor(ry) or -999
    local log = (NS.db and NS.db.log) or {}
    for i = #log, 1, -1 do
      local e = log[i]
      if e and not e.separator then
        local ok, res = pcall(EntryColumns, e)
        p.renderOK = ok
        if ok then
          p.sampleName = (res and res.name and res.name ~= "") and "ok" or "EMPTY"
        else
          p.renderErr = tostring(res)
        end
        break
      end
    end
  end
  -- Container geometry (paged plain list, no scrollframe).
  p.contH = (listContainer and math.floor(listContainer:GetHeight() or 0)) or -1
  p.contW = (listContainer and math.floor(listContainer:GetWidth() or 0)) or -1
  -- IsVisible (not IsShown): false here with IsShown true = hidden ancestor.
  p.frameVis = logFrame and logFrame:IsVisible() or false
  p.contVis = listContainer and listContainer:IsVisible() or false
  if r1 then
    p.r1vis = r1:IsVisible()
    p.r1w = math.floor(r1:GetWidth() or -1)
  end
  for _, r in ipairs(rows) do
    if r.entry and not r.entry.separator and r.cols and r.cols.name then
      local tx = r.cols.name:GetText() or ""
      local clean = tx:gsub("|T.-|t", "[icon]"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      p.firstText = clean:sub(1, 50)
      break
    end
  end
  return p
end

function NS.ToggleLogUI(force)
  if not logFrame then NS.BuildLogUI() end
  local wasShown = logFrame:IsShown()
  if force == true then logFrame:Show()
  elseif force == false then logFrame:Hide()
  else
    if logFrame:IsShown() then logFrame:Hide() else logFrame:Show() end
  end
  -- Newest-first list: always open on page 1.
  if logFrame:IsShown() and not wasShown then NS.logPage = 1 end
  NS.RefreshLogUI()
end

function NS.BuildLogUI()
  if logFrame then return end
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  logFrame = CreateFrame("Frame", "LFGAlertLogFrame", UIParent, template)
  logFrame:SetSize(FRAME_W, FRAME_H)
  logFrame:SetPoint("CENTER")
  logFrame:SetMovable(true)
  logFrame:EnableMouse(true)
  logFrame:RegisterForDrag("LeftButton")
  logFrame:SetScript("OnDragStart", logFrame.StartMoving)
  logFrame:SetScript("OnDragStop", logFrame.StopMovingOrSizing)
  logFrame:SetClampedToScreen(true)
  if logFrame.SetBackdrop then
    logFrame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    -- Group-Finder chrome: dark navy + gold border.
    logFrame:SetBackdropColor(0.04, 0.06, 0.12, 0.96)
    logFrame:SetBackdropBorderColor(0.85, 0.68, 0.3, 1)
  end

  local bell = logFrame:CreateTexture(nil, "OVERLAY")
  bell:SetSize(26, 26)
  bell:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 16, -10)
  bell:SetTexture("Interface\\Icons\\INV_Misc_Bell_01")

  local title = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", bell, "RIGHT", 8, 0)
  title:SetText("LFGAlert Applicant Log")
  title:SetTextColor(1, 0.82, 0)

  local sub = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sub:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 50, -40)
  sub:SetText("Role  •  Spec  •  Key  •  iLvl  •  M+ score (RIO if installed)")
  sub:SetTextColor(0.7, 0.7, 0.7)

  local close = CreateFrame("Button", nil, logFrame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", -4, -4)

  local clear = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
  clear:SetSize(90, 22)
  clear:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", -32, -34)
  clear:SetText("Clear Log")
  if clear.Text then clear.Text:SetTextColor(1, 0.4, 0.35) end
  clear:SetScript("OnClick", function() NS.ClearLog() end)

  local test = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
  test:SetSize(80, 22)
  test:SetPoint("RIGHT", clear, "LEFT", -6, 0)
  test:SetText("Test sound")
  test:SetScript("OnClick", function() NS.PlayAlertSound() end)

  countLabel = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  countLabel:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", -36, -62)
  countLabel:SetJustifyH("RIGHT")
  countLabel:SetTextColor(0.8, 0.8, 0.8)

  -- Filter + search bar: search box + Status / Class / Key dropdowns.
  searchBox = CreateFrame("EditBox", nil, logFrame, "SearchBoxTemplate")
  searchBox:SetSize(160, 22)
  searchBox:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 14, -62)
  searchBox:SetAutoFocus(false)
  searchBox:SetMaxLetters(60)
  searchBox:SetScript("OnTextChanged", function(self)
    NS.logFilter.query = (self:GetText() or ""):lower()
    NS.RefreshLogUI()
  end)
  searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
  -- SearchBoxTemplate shows its own clear button; add hint text if supported.
  if searchBox.Instructions then
    searchBox.Instructions:SetText("Search...")
  end

  local function DropLabel(text, x, w)
    local fs = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", logFrame, "TOPLEFT", x, -73)
    fs:SetWidth(w)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
  end

  DropLabel("Status:", 184, 42)
  filterButton = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
  filterButton:SetSize(100, 22)
  filterButton:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 228, -62)
  filterButton:SetText("Status: All")
  filterButton:SetScript("OnClick", function(self) ShowFilterMenu(self) end)

  DropLabel("Class:", 336, 38)
  classBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
  classBtn:SetSize(110, 22)
  classBtn:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 376, -62)
  classBtn:SetText("Class: All")
  classBtn:SetScript("OnClick", function(self) ShowClassMenu(self) end)

  DropLabel("Key:", 494, 30)
  keyBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
  keyBtn:SetSize(80, 22)
  keyBtn:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 526, -62)
  keyBtn:SetText("Key: All")
  keyBtn:SetScript("OnClick", function(self) ShowKeyMenu(self) end)

  -- Header row: same insets + same COLS spec as every data row, so each
  -- heading sits exactly above its values.
  local headerFrame = CreateFrame("Frame", nil, logFrame)
  headerFrame:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 12, -88)
  headerFrame:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", -32, -88)
  headerFrame:SetHeight(14)
  do
    local x = 4 + 2
    for _, c in ipairs(COLS) do
      local fs = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetJustifyH(c.justify)
      fs:SetWordWrap(false)
      fs:SetTextColor(1, 0.82, 0)
      fs:SetText(c.label)
      if c.key == "note" then
        fs:SetPoint("LEFT", headerFrame, "LEFT", x, 0)
        fs:SetPoint("RIGHT", headerFrame, "RIGHT", -2, 0)
      else
        fs:SetPoint("LEFT", headerFrame, "LEFT", x, 0)
        fs:SetWidth(c.width)
        x = x + c.width + ROW_GAP
      end
    end
  end

  local sep = logFrame:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(1, 1, 1, 0.15)
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 16, -104)
  sep:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", -36, -104)

  -- Plain list container (deliberately NOT a ScrollFrame): rows parented
  -- here paint 1:1 with no viewport, clipping, or scrollbar state involved.
  listContainer = CreateFrame("Frame", nil, logFrame)
  listContainer:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 12, -108)
  listContainer:SetPoint("BOTTOMRIGHT", logFrame, "BOTTOMRIGHT", -32, 30)
  listContainer:EnableMouse(true)
  listContainer:SetScript("OnMouseWheel", function(_, delta)
    NS.LogPageDelta(delta > 0 and -1 or 1)
  end)

  NS._rowsBuilt, NS._rowBuildError = 0, nil
  for i = 1, PAGE_SIZE do
    local ok, row = pcall(MakeRow, listContainer, i)
    if ok and row then
      rows[i] = row
      NS._rowsBuilt = NS._rowsBuilt + 1
    else
      NS._rowBuildError = "row " .. i .. ": " .. tostring(row)
      break
    end
  end

  prevBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
  prevBtn:SetSize(90, 22)
  prevBtn:SetPoint("BOTTOMLEFT", logFrame, "BOTTOMLEFT", 14, 12)
  prevBtn:SetText("< Newer")
  prevBtn:SetScript("OnClick", function() NS.LogPageDelta(-1) end)

  nextBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
  nextBtn:SetSize(90, 22)
  nextBtn:SetPoint("BOTTOMRIGHT", logFrame, "BOTTOMRIGHT", -14, 12)
  nextBtn:SetText("Older >")
  nextBtn:SetScript("OnClick", function() NS.LogPageDelta(1) end)

  -- Slash shortcut hint
  local hint = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("BOTTOM", logFrame, "BOTTOM", 0, 14)
  hint:SetText("Left-click whisper  •  Right-click invite/decline  •  /lfgalert filter <status>")
  hint:SetTextColor(0.55, 0.55, 0.55)

  logFrame:Hide()
  NS.RefreshLogUI()
end
