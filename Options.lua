-- LFGAlert - Options.lua
-- Minimap button + Blizzard Settings panel.
local ADDON_NAME, TITLE = ...
LFGAlert = LFGAlert or {}
local NS = LFGAlert
local L = NS.L or {}
local function l(key, fallback) return L[key] or fallback end

-- ---------------------------------------------------------------------------
-- Minimap button (no library, Blizzard-style)
-- ---------------------------------------------------------------------------

local mmButton
local ShowMinimapMenu -- forward: defined below, used by the minimap OnClick

local function MinimapPos(angleDeg)
  local rad = math.rad(angleDeg or 220)
  local x, y = math.cos(rad), math.sin(rad)
  -- Minimap is ~140px radius; keep button on the edge.
  return x * 80, y * 80
end

function NS.BuildMinimapButton()
  if mmButton then
    mmButton:SetShown(NS.db and NS.db.showMinimapButton ~= false)
    return
  end
  mmButton = CreateFrame("Button", "LFGAlertMinimapButton", Minimap)
  mmButton:SetSize(31, 31)
  mmButton:SetFrameStrata("MEDIUM")
  mmButton:SetFrameLevel(8)
  mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local overlay = mmButton:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetPoint("TOPLEFT", 0, 0)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  local bg = mmButton:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER", 0, 1)
  bg:SetTexture("Interface\\Icons\\INV_Misc_Bell_01")

  local function UpdatePos()
    local mx, my = MinimapPos(NS.db and NS.db.minimapAngle or 220)
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", mx, my)
  end
  UpdatePos()
  mmButton.UpdatePos = UpdatePos

  mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mmButton:RegisterForDrag("LeftButton")
  mmButton:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function(s)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    NS.db.minimapAngle = angle
    UpdatePos()
  end) end)
  mmButton:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  mmButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
      NS.ToggleLogUI()
    else
      ShowMinimapMenu(self)
    end
  end)
  mmButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("LFGAlert")
    GameTooltip:AddLine(l("mm_open", "Left-click: open applicant log"), 1, 1, 1)
    GameTooltip:AddLine(l("mm_menu", "Right-click: options menu (sound, mute, settings)"), 1, 1, 1)
    GameTooltip:AddLine(l("mm_drag", "Drag: move minimap icon"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  mmButton:SetShown(NS.db and NS.db.showMinimapButton ~= false)
end

-- Right-click menu: log, quick toggles, settings. Same MenuUtil/EasyMenu
-- pattern as the log rows, so it works on every client generation.
ShowMinimapMenu = function(anchor)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle("LFGAlert")
      root:CreateButton(l("mm_menu_log", "Open applicant log"), function()
        if NS.ToggleLogUI then NS.ToggleLogUI(true) end
      end)
      root:CreateCheckbox(l("mm_menu_sound", "Sound alerts"),
        function() return NS.db.soundEnabled end,
        function(v) NS.db.soundEnabled = v end)
      root:CreateCheckbox(l("mm_menu_mute", "Mute everything"),
        function() return NS.db.muteAll end,
        function(v) NS.db.muteAll = v end)
      root:CreateDivider()
      root:CreateButton(l("mm_menu_settings", "Settings"), function()
        if NS.OpenSettings then NS.OpenSettings() end
      end)
    end)
    return
  end
  if not LFGAlertMinimapMenu then
    CreateFrame("Frame", "LFGAlertMinimapMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local menu = {
    { text = "LFGAlert", isTitle = true, notCheckable = true },
    { text = l("mm_menu_log", "Open applicant log"), notCheckable = true,
      func = function() if NS.ToggleLogUI then NS.ToggleLogUI(true) end end },
    { text = l("mm_menu_sound", "Sound alerts"), checked = NS.db.soundEnabled, notCheckable = false,
      func = function() NS.db.soundEnabled = not NS.db.soundEnabled end },
    { text = l("mm_menu_mute", "Mute everything"), checked = NS.db.muteAll, notCheckable = false,
      func = function() NS.db.muteAll = not NS.db.muteAll end },
    { text = l("mm_menu_settings", "Settings"), notCheckable = true,
      func = function() if NS.OpenSettings then NS.OpenSettings() end end },
  }
  EasyMenu(menu, LFGAlertMinimapMenu, "cursor", 0, 0, "MENU")
end

-- ---------------------------------------------------------------------------
-- Settings panel (works on Retail 11+/12+ and falls back to old API)
-- ---------------------------------------------------------------------------

local optionChecks = {} -- live-synced: preset buttons elsewhere change these values

local function Checkbox(parent, label, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  cb.Text:SetText(label)
  cb._get = get
  optionChecks[#optionChecks + 1] = cb
  cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
  cb:SetScript("OnClick", function(self) set(self:GetChecked()) end)
  return cb
end

-- Presets/buttons elsewhere in the panel change db values directly; this
-- repaints every checkbox so the panel never shows stale states.
local function SyncCheckboxes()
  for _, cb in ipairs(optionChecks) do
    if cb._get then cb:SetChecked(cb._get()) end
  end
end

local function Slider(parent, label, minV, maxV, step, get, set)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetSize(280, 20)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)
  s.Low:SetText(tostring(minV))
  s.High:SetText(tostring(maxV))
  local function paint(v)
    v = math.floor((v or 0) + 0.5)
    s.Text:SetText(label .. ": " .. tostring(v) .. (v <= 0 and " (off)" or ""))
  end
  s:SetScript("OnShow", function(self)
    local v = get() or 0
    self:SetValue(v)
    paint(v)
  end)
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v + 0.5)
    paint(v)
    set(v)
    if NS.RefreshLogUI then NS.RefreshLogUI(true) end
  end)
  return s
end

-- Float variant (e.g. window scale) with 2-decimal paint.
local function FloatSlider(parent, label, minV, maxV, step, get, set)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetSize(280, 20)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)
  s.Low:SetText(string.format("%.2f", minV))
  s.High:SetText(string.format("%.2f", maxV))
  local function paint(v)
    s.Text:SetText(label .. ": " .. string.format("%.2f", v or 1))
  end
  s:SetScript("OnShow", function(self)
    local v = get() or 1
    self:SetValue(v)
    paint(v)
  end)
  s:SetScript("OnValueChanged", function(self, v)
    paint(v)
    set(v)
  end)
  return s
end

function NS.BuildOptions()
  local panel = CreateFrame("Frame", "LFGAlertOptionsPanel")
  panel.name = "LFGAlert"

  -- Scrollable content so every option fits on any client size.
  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", 0, 8)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(620, 920)
  scroll:SetScrollChild(content)

  local y = -8
  local function Section(text)
    y = y - 20
    local h = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    h:SetText(text)
    h:SetTextColor(1, 0.82, 0)
    y = y - 28
  end
  local function AddCB(label, get, set)
    local cb = Checkbox(content, label, get, set)
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y)
    y = y - 30
    return cb
  end
  local function Note(text, h)
    local d = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y)
    d:SetWidth(560)
    d:SetJustifyH("LEFT")
    d:SetText(text)
    d:SetTextColor(0.7, 0.7, 0.7)
    y = y - (h or 22)
  end
  local function ButtonsRow(defs)
    local bx = 24
    for _, def in ipairs(defs) do
      local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
      b:SetSize(def[2], 24)
      b:SetPoint("TOPLEFT", content, "TOPLEFT", bx, y)
      b:SetText(def[1])
      b:SetScript("OnClick", def[3])
      bx = bx + def[2] + 10
    end
    y = y - 32
  end

  local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  title:SetText(l("opt_title", "LFGAlert - Group Finder applicant alerts"))
  y = y - 24
  local addonVer = "?"
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, vv = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
    if ok and vv then addonVer = vv end
  elseif GetAddOnMetadata then
    local ok, vv = pcall(GetAddOnMetadata, ADDON_NAME, "Version")
    if ok and vv then addonVer = vv end
  end
  local verText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  verText:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
  verText:SetTextColor(0.6, 0.6, 0.6)
  verText:SetText(l("opt_version_fmt", "Version %s  •  build %s  •  /lfgalert for commands"):format(tostring(addonVer), tostring(NS.BUILD or "?")))
  y = y - 20

  Section(l("sec_mute", "Mute"))
  Note(l("note_mute", "Master switches for every noisy part. Mute everything overrides the rows below; muted items stay fully logged."), 34)
  do
    local function MuteCB(label, key, extra)
      local cb = Checkbox(content, label,
        function() return NS.db[key] end,
        function(v) NS.db[key] = v if extra then extra(v) end end)
      cb:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y)
      y = y - 30
      return cb
    end
    MuteCB(l("mute_all", "Mute everything (sound, chat, screen, popup)"), "muteAll")
    MuteCB(l("mute_sound", "Sound alerts"), "soundEnabled")
    MuteCB(l("mute_chat", "Chat messages"), "chatMessage")
    MuteCB(l("mute_screen", "Screen warnings"), "raidWarning")
    MuteCB(l("mute_popup", "Group Finder popup"), "autoOpenLFG")
    MuteCB(l("mute_flash", "Taskbar flash"), "flashTaskbar")
    MuteCB(l("mute_summary", "Session summary on delist"), "statsSummary")
    MuteCB(l("mute_minimap", "Minimap button"), "showMinimapButton",
      function(v) if mmButton then mmButton:SetShown(v) end end)
  end

  Section(l("sec_general", "General"))
  AddCB(l("cb_enable", "Enable LFGAlert"), function() return NS.db.enabled end,
    function(v) NS.db.enabled = v end)
  AddCB(l("cb_minimap", "Show minimap button (left: log, right: sound, drag: move)"), function() return NS.db.showMinimapButton ~= false end,
    function(v) NS.db.showMinimapButton = v; if mmButton then mmButton:SetShown(v) end end)
  AddCB(l("cb_autoopen", "Open Group Finder applicants on new queue"), function() return NS.db.autoOpenLFG ~= false end,
    function(v) NS.db.autoOpenLFG = v end)
  AddCB(l("cb_ownkey", "Use my own keystone for dungeon/key when listing text is hidden"), function() return NS.db.assumeOwnKey ~= false end,
    function(v) NS.db.assumeOwnKey = v end)

  Section(l("sec_window", "Log Window"))
  local scaleSlider = FloatSlider(content, l("slider_scale", "Log window scale"), 0.6, 1.5, 0.05,
    function() return (NS.db.ui and NS.db.ui.scale) or 1 end,
    function(v) NS.SetUIScale(v) end)
  scaleSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y)
  y = y - 54
  ButtonsRow({
    { l("btn_reset_ui", "Reset window position & size"), 220, function()
        if NS.ResetUI then NS.ResetUI() end
        print("|cffff2020[LFGAlert]|r Log window reset.")
      end },
  })
  AddCB(l("cb_groupbykey", 'Group rows by key ("+10 Altar of Fangs (3)")'), function() return NS.db.groupByKey ~= false end,
    function(v) NS.db.groupByKey = v if NS.RefreshLogUI then NS.RefreshLogUI(true) end end)

  Section(l("sec_alerts", "Alerts & Sound"))
  AddCB(l("cb_sound", "Play sound on new application"), function() return NS.db.soundEnabled end,
    function(v) NS.db.soundEnabled = v end)
  AddCB(l("cb_rw", "Show raid-warning in screen center"), function() return NS.db.raidWarning end,
    function(v) NS.db.raidWarning = v end)
  AddCB(l("cb_chat", "Show chat message"), function() return NS.db.chatMessage end,
    function(v) NS.db.chatMessage = v end)
  AddCB(l("cb_flash", "Flash taskbar on new application"), function() return NS.db.flashTaskbar end,
    function(v) NS.db.flashTaskbar = v end)

  Note(l("note_presets", "Presets (click to preview):"))
  local eb -- forward declaration: presets update the ID box below
  do
    local bx, bw = 24, 110
    for _, p in ipairs({ { l("preset_rw", "Raid Warning"), 8959 }, { l("preset_ready", "Ready Check"), 8960 }, { l("preset_level", "Level Up"), 12867 } }) do
      local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
      b:SetSize(bw, 22)
      b:SetPoint("TOPLEFT", content, "TOPLEFT", bx, y)
      b:SetText(p[1])
      b:SetScript("OnClick", function()
        NS.db.soundID = p[2]
        NS.db.useCustomSound = false
        NS.db.soundEnabled = true
        if eb then eb:SetText(tostring(p[2])) end
        SyncCheckboxes()
        NS.PlayAlertSound()
      end)
      bx = bx + bw + 8
    end
    y = y - 30
  end

  local soundLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  soundLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y - 4)
  soundLabel:SetText(l("lbl_sound_id", "Sound ID:"))

  eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
  eb:SetSize(100, 24)
  eb:SetPoint("LEFT", soundLabel, "RIGHT", 10, 0)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetScript("OnShow", function(self) self:SetText(tostring(NS.db.soundID or 8959)) end)
  eb:SetScript("OnEnterPressed", function(self)
    local id = tonumber(self:GetText())
    if id then
      NS.db.soundID = id
      NS.db.useCustomSound = false
      NS.db.soundEnabled = true
      SyncCheckboxes()
      NS.PlayAlertSound()
      print("|cffff2020[LFGAlert]|r Sound set to " .. id)
    end
    self:ClearFocus()
  end)

  local testBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  testBtn:SetSize(110, 24)
  testBtn:SetPoint("LEFT", eb, "RIGHT", 10, 0)
  testBtn:SetText(l("btn_test", "Test sound"))
  testBtn:SetScript("OnClick", function() NS.PlayAlertSound() end)
  y = y - 34

  local customCB = Checkbox(content, l("cb_custom", "Use custom sound file instead of Sound ID"), function() return NS.db.useCustomSound end,
    function(v) NS.db.useCustomSound = v end)
  customCB:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y)
  y = y - 30

  local pathLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  pathLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 48, y - 4)
  pathLabel:SetText(l("lbl_file_path", "File path:"))

  local pathBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
  pathBox:SetSize(280, 24)
  pathBox:SetPoint("LEFT", pathLabel, "RIGHT", 10, 0)
  pathBox:SetAutoFocus(false)
  pathBox:SetScript("OnShow", function(self) self:SetText(NS.db.customSoundPath or "") end)
  pathBox:SetScript("OnEnterPressed", function(self)
    local p = self:GetText() or ""
    if strtrim then p = strtrim(p) else p = p:match("^%s*(.-)%s*$") end
    if p == "" then
      NS.db.useCustomSound = false
      SyncCheckboxes()
      print("|cffff2020[LFGAlert]|r Custom sound OFF.")
    else
      NS.db.customSoundPath = p
      NS.db.useCustomSound = true
      NS.db.soundEnabled = true
      SyncCheckboxes()
      NS.PlayAlertSound()
      print("|cffff2020[LFGAlert]|r Custom sound set. Playing...")
    end
    self:ClearFocus()
  end)
  y = y - 30
  Note(l("note_custom_example", "Example: Interface\\AddOns\\LFGAlert\\Sounds\\alert.ogg  (drop your own .ogg/.mp3 into the addon folder; restart WoW so it sees new files)"), 34)

  Section(l("sec_roles", "Alerts by role"))
  Note(l("note_roles", "Uncheck a role to mute it per channel. Unknown roles (no data yet) always alert. Log rows, stats and auto-decline are unaffected."), 34)
  do
    local roles = {
      { store = "TANK", show = l("role_tank", "Tank") },
      { store = "HEALER", show = l("role_healer", "Heal") },
      { store = "DAMAGER", show = l("role_dps", "DPS") },
    }
    local function RoleRow(rowLabel, channel)
      local lab = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      lab:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y - 6)
      lab:SetWidth(110)
      lab:SetJustifyH("LEFT")
      lab:SetText(rowLabel)
      local bx = 140
      for _, r in ipairs(roles) do
        local store = r.store
        local cb = Checkbox(content, r.show,
          function()
            local c = NS.db.alertRoles and NS.db.alertRoles[channel]
            return c == nil or c[store] ~= false
          end,
          function(v)
            NS.db.alertRoles = NS.db.alertRoles or {}
            NS.db.alertRoles[channel] = NS.db.alertRoles[channel] or {}
            NS.db.alertRoles[channel][store] = v
          end)
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", bx, y)
        bx = bx + 95
      end
      y = y - 30
    end
    RoleRow(l("row_sound", "Sound for:"), "sound")
    RoleRow(l("row_chat", "Chat for:"), "chat")
    RoleRow(l("row_screen", "Screen alert for:"), "screen")
    RoleRow(l("row_popup", "Popup for:"), "popup")
  end

  Section(l("sec_req", "Requirements (highlight * + auto-decline)"))
  Note(l("note_req", "Rows at/above these get a * and green numbers, and auto-decline judges by them. 0 = off. Exact values via /lfgalert minilvl <n> and /lfgalert minscore <n>."), 34)

  local ilvlSlider = Slider(content, l("slider_ilvl", "Min item level"), 0, 800, 1,
    function() return NS.db.minIlvl or 0 end,
    function(v) NS.db.minIlvl = v end)
  ilvlSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y)
  y = y - 54

  local scoreSlider = Slider(content, l("slider_score", "Min M+ score"), 0, 5000, 5,
    function() return NS.db.minScore or 0 end,
    function(v) NS.db.minScore = v end)
  scoreSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y)
  y = y - 54

  AddCB(l("cb_autodecline", "Auto-decline below thresholds (only with real data)"), function() return NS.db.autoDecline end,
    function(v) NS.db.autoDecline = v end)

  Section(l("sec_data", "Data & Stats"))
  local statsText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statsText:SetPoint("TOPLEFT", content, "TOPLEFT", 24, y)
  statsText:SetWidth(560)
  statsText:SetJustifyH("LEFT")
  local function refreshStatsText()
    local D = NS.Data()
    local st = D and D.stats and D.stats.total
    if st then
      local au = st.auto or 0
      statsText:SetText(l("stats_summary_fmt", "All time: %d queued • %d accepted • %d declined%s"):format(
        st.queued or 0, st.accepted or 0, (st.declined or 0) + au,
        au > 0 and l("stats_auto_paren", " (%d auto)"):format(au) or ""))
    else
      statsText:SetText(l("no_stats", "No stats yet."))
    end
  end
  refreshStatsText()
  y = y - 24
  AddCB(l("cb_perchar", "Separate log & stats per character (default: shared)"), function() return NS.db.perCharLog end,
    function(v) if NS.SetPerCharLog then NS.SetPerCharLog(v) else NS.db.perCharLog = v end end)
  Note(l("note_perchar", "Switching keeps both histories; each character starts fresh."), 22)
  ButtonsRow({
    { l("btn_show_stats", "Show stats"), 110, function() NS.PrintStats() end },
    { l("btn_reset_stats", "Reset stats"), 110, function()
        NS.Data().stats = { sessions = {}, total = { queued = 0, invited = 0, accepted = 0, declined = 0, auto = 0, gone = 0 } }
        refreshStatsText()
        print("|cffff2020[LFGAlert]|r Stats reset.")
      end },
    { l("btn_clear_log", "Clear log"), 110, function()
        NS.ClearLog()
        print("|cffff2020[LFGAlert]|r Log cleared.")
      end },
  })
  Note(l("note_stats", "Stats keep the last 30 listings plus all-time totals. Per-listing summary prints to chat on delist."))

  Section(l("sec_about", "About"))
  Note(l("note_about", "Log window: scroll to browse history, click column headers to sort, left-click selects a row, right-click for whisper / invite / decline. Full command list: /lfgalert (no args)."), 34)
  ButtonsRow({
    { l("btn_open_log", "Open applicant log"), 150, function() NS.ToggleLogUI(true) end },
  })

  content:SetHeight(-y + 20)
  content:SetScript("OnShow", function() refreshStatsText() SyncCheckboxes() end)

  -- Register category: new Settings API first, old InterfaceOptions fallback.
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(cat)
    NS._settingsCategory = cat
  elseif InterfaceOptions_AddCategory then
    pcall(InterfaceOptions_AddCategory, panel)
  end
end

-- Open the settings panel (used by /lfgalert config and the minimap menu).
function NS.OpenSettings()
  if Settings and Settings.OpenToCategory and NS._settingsCategory then
    local okC, id = pcall(function() return NS._settingsCategory:GetID() end)
    if okC and id then pcall(Settings.OpenToCategory, id) return end
  end
  if InterfaceOptionsFrame_OpenToCategory then
    pcall(InterfaceOptionsFrame_OpenToCategory, "LFGAlert")
  else
    print("|cffff2020[LFGAlert]|r Open with Esc > Options > AddOns > LFGAlert")
  end
end
