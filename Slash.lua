-- LFGAlert - Slash.lua (commands + settings export/import)
LFGAlert = LFGAlert or {}
local NS = LFGAlert

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_LFGALERT1 = "/lfgalert"
SLASH_LFGALERT2 = "/lfga"
SlashCmdList["LFGALERT"] = function(msg)
  msg = (msg or ""):lower()
  if strtrim then msg = strtrim(msg) else msg = msg:match("^%s*(.-)%s*$") end
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "show" or cmd == "log" then
    if NS.ToggleLogUI then NS.ToggleLogUI(true) end
  elseif cmd == "hide" then
    if NS.ToggleLogUI then NS.ToggleLogUI(false) end
  elseif cmd == "toggle" then
    if NS.ToggleLogUI then NS.ToggleLogUI() end
  elseif cmd == "clear" then
    NS.ClearLog()
    print("|cffff2020[LFGAlert]|r Log cleared.")
  elseif cmd == "test" then
    NS.PlayAlertSound()
    NS.ApplicantToast("LFGAlert test: sound + warning OK")
    ChatMessage("Test alert OK. List a group and have someone apply to see real entries. (Fake log row added.)")
    -- Add a fake row so users can try right-click whisper/invite UI instantly.
    NS.AddLogEntry(0, nil, "applied", {
      status = "applied", numMembers = 1, comment = "Test entry (/lfgalert clear to remove)",
      listing = { dungeon = "AOF", dungeonFull = "Altar of Fangs", key = 5, title = "Test group" },
      members = { { name = UnitName("player") or "TestPlayer", class = select(2, UnitClass("player")) or "WARRIOR",
        localizedClass = select(1, UnitClass("player")) or "Warrior", level = UnitLevel("player") or 80,
        itemLevel = 600, dungeonScore = 1500, rioScore = 0, specName = "Test", role = "DAMAGER" } },
    }, true)
    if NS.ToggleLogUI then NS.ToggleLogUI(true) end
  elseif cmd == "sound" then
    local id = tonumber(rest)
    if id then
      NS.db.soundID = id
      NS.db.useCustomSound = false
      NS.db.soundEnabled = true
      print("|cffff2020[LFGAlert]|r Sound set to " .. id .. " (playing...)")
      NS.PlayAlertSound()
    else
      NS.db.soundEnabled = not NS.db.soundEnabled
      print("|cffff2020[LFGAlert]|r Sound " .. (NS.db.soundEnabled and "ON" or "OFF"))
    end
  elseif cmd == "rolesound" then
    -- /lfgalert rolesound tank|healer|dps <id>|off  (off/0 = global sound)
    local map = {
      tank = "TANK", t = "TANK",
      healer = "HEALER", heal = "HEALER", h = "HEALER",
      dps = "DAMAGER", damager = "DAMAGER", d = "DAMAGER",
    }
    local which, val = rest:match("^(%S+)%s*(.-)$")
    local key = which and map[which:lower()]
    if not key then
      print("|cffff2020[LFGAlert]|r Usage: /lfgalert rolesound tank|healer|dps <id>|off")
      for _, rk in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local rs = NS.db.roleSounds and NS.db.roleSounds[rk]
        print(string.format("  %s: %s", rk:lower(), rs and tostring(rs) or "global"))
      end
    elseif val == "" or val == "off" or val == "0" then
      NS.db.roleSounds = NS.db.roleSounds or {}
      NS.db.roleSounds[key] = nil
      print("|cffff2020[LFGAlert]|r " .. key:lower() .. " sound: global")
    else
      local rid = tonumber(val)
      if rid and rid > 0 then
        NS.db.roleSounds = NS.db.roleSounds or {}
        NS.db.roleSounds[key] = rid
        print("|cffff2020[LFGAlert]|r " .. key:lower() .. " sound set to " .. rid .. " (playing...)")
        NS.PlayAlertSound(nil, key)
      else
        print("|cffff2020[LFGAlert]|r Give a SoundKit ID or 'off'.")
      end
    end
  elseif cmd == "rolesoundfile" then
    -- /lfgalert rolesoundfile tank|healer|dps <path>|off  (overrides the ID)
    local map = {
      tank = "TANK", t = "TANK",
      healer = "HEALER", heal = "HEALER", h = "HEALER",
      dps = "DAMAGER", damager = "DAMAGER", d = "DAMAGER",
    }
    local which, val = rest:match("^(%S+)%s*(.-)$")
    local key = which and map[which:lower()]
    if not key then
      print("|cffff2020[LFGAlert]|r Usage: /lfgalert rolesoundfile tank|healer|dps <path>|off")
      print("  Example: /lfgalert rolesoundfile tank Interface\\AddOns\\LFGAlert\\Sounds\\tank.ogg")
    elseif val == "" or val == "off" or val == "clear" then
      NS.db.roleSoundFiles = NS.db.roleSoundFiles or {}
      NS.db.roleSoundFiles[key] = ""
      print("|cffff2020[LFGAlert]|r " .. key:lower() .. " custom file OFF (role SoundKit ID applies again).")
    else
      NS.db.roleSoundFiles = NS.db.roleSoundFiles or {}
      NS.db.roleSoundFiles[key] = val
      print("|cffff2020[LFGAlert]|r " .. key:lower() .. " custom file set (playing...)")
      local ch = NS.db.useMasterChannel and "Master" or nil
      pcall(PlaySoundFile, val, ch)
    end
  elseif cmd == "soundfile" then
    -- /lfgalert soundfile Interface\AddOns\LFGAlert\Sounds\alert.ogg
    -- /lfgalert soundfile off  (back to SoundKit ID)
    if rest == "" or rest == "off" or rest == "clear" then
      NS.db.useCustomSound = false
      NS.db.customSoundPath = ""
      print("|cffff2020[LFGAlert]|r Custom sound OFF, using SoundKit ID " .. tostring(NS.db.soundID))
    else
      -- NOTE: slash input arrives lowercased; restore case-insensitive path use as-is.
      -- WoW file paths are case-insensitive, so this is fine for Interface\ paths.
      NS.db.customSoundPath = rest
      NS.db.useCustomSound = true
      NS.db.soundEnabled = true
      print("|cffff2020[LFGAlert]|r Custom sound set to \"" .. rest .. "\" (playing...)")
      NS.PlayAlertSound()
    end
  elseif cmd == "minilvl" or cmd == "minilv" or cmd == "minlvl" then
    local n = tonumber(rest) or 0
    NS.db.minIlvl = math.max(0, math.floor(n))
    print("|cffff2020[LFGAlert]|r Min item level: " .. (NS.db.minIlvl > 0 and tostring(NS.db.minIlvl) or "OFF"))
    if NS.RefreshLogUI then NS.RefreshLogUI() end
  elseif cmd == "minscore" then
    local n = tonumber(rest) or 0
    NS.db.minScore = math.max(0, math.floor(n))
    print("|cffff2020[LFGAlert]|r Min M+ score: " .. (NS.db.minScore > 0 and tostring(NS.db.minScore) or "OFF"))
    if NS.RefreshLogUI then NS.RefreshLogUI() end
  elseif cmd == "filter" then
    -- /lfgalert filter queued|invited|accepted|declined|gone|all
    if NS.SetLogFilter then
      NS.SetLogFilter(rest ~= "" and rest or "ALL")
      if NS.ToggleLogUI then NS.ToggleLogUI(true) end
    end
  elseif cmd == "class" then
    -- /lfgalert class warrior|mage|...|all
    if NS.SetLogClassFilter then
      NS.SetLogClassFilter(rest ~= "" and rest or "ALL")
      if NS.ToggleLogUI then NS.ToggleLogUI(true) end
    end
  elseif cmd == "minkey" or cmd == "key" then
    -- /lfgalert minkey 10  (0 = all keys)
    if NS.SetLogMinKey then
      NS.SetLogMinKey(tonumber(rest) or 0)
      if NS.ToggleLogUI then NS.ToggleLogUI(true) end
    end
  elseif cmd == "window" then
    -- /lfgalert window [on|off] - auto-open Group Finder applicants on queue
    if rest == "on" then NS.db.autoOpenLFG = true
    elseif rest == "off" then NS.db.autoOpenLFG = false
    else NS.db.autoOpenLFG = not NS.db.autoOpenLFG end
    print("|cffff2020[LFGAlert]|r Auto-open LFG window " .. (NS.db.autoOpenLFG and "ON" or "OFF"))
  elseif cmd == "mute" then
    -- /lfgalert mute [on|off] - master mute for sound/chat/screen/popup
    if rest == "on" then NS.db.muteAll = true
    elseif rest == "off" then NS.db.muteAll = false
    else NS.db.muteAll = not NS.db.muteAll end
    print("|cffff2020[LFGAlert]|r All alerts " .. (NS.db.muteAll and "MUTED" or "ON") .. " (log keeps recording)")
  elseif cmd == "trace" then
    -- /lfgalert trace [on|off] - one-line alert decision dump per queue
    if rest == "on" then NS.db.traceAlerts = true
    elseif rest == "off" then NS.db.traceAlerts = nil
    else NS.db.traceAlerts = not NS.db.traceAlerts and true or nil end
    print("|cffff2020[LFGAlert]|r Alert tracing " .. (NS.db.traceAlerts and "ON" or "OFF"))
  elseif cmd == "groupbykey" then
    -- /lfgalert groupbykey [on|off] - group log rows under their key
    if rest == "on" then NS.db.groupByKey = true
    elseif rest == "off" then NS.db.groupByKey = false
    else NS.db.groupByKey = not NS.db.groupByKey end
    print("|cffff2020[LFGAlert]|r Group by key " .. (NS.db.groupByKey and "ON" or "OFF"))
    if NS.RefreshLogUI then NS.RefreshLogUI(true) end
  elseif cmd == "open" then
    NS.OpenApplicants()
  elseif cmd == "mute" then
    if rest == "on" then NS.db.muteAll = true
    elseif rest == "off" then NS.db.muteAll = false
    else NS.db.muteAll = not NS.db.muteAll end
    print("|cffff2020[LFGAlert]|r All alerts " .. (NS.db.muteAll and "MUTED" or "ON") .. " (log keeps recording)")
  elseif cmd == "resetui" then
    if NS.ResetUI then NS.ResetUI() end
    print("|cffff2020[LFGAlert]|r Log window reset (position / size / scale).")
  elseif cmd == "config" or cmd == "options" or cmd == "settings" then
    if NS.OpenSettings then NS.OpenSettings() end
  elseif cmd == "mouse" then
    -- Hover the empty list, wait 3s, then see which frames eat the mouse.
    print("|cffff2020[LFGAlert]|r Hover the EMPTY list area now (printing in 3s)...")
    C_Timer.After(3, function()
      local foci = (GetMouseFoci and GetMouseFoci()) or {}
      if #foci == 0 then
        print("  (mouse is over the 3D world, not on any frame)")
      end
      for i = 1, math.min(#foci, 6) do
        local f = foci[i]
        local nm = (f.GetName and f:GetName()) or "?"
        print("  focus[" .. i .. "]=" .. tostring(nm) .. " (" .. tostring(f:GetObjectType()) .. ")")
      end
    end)
  elseif cmd == "listing" then
    -- Dump what Blizzard reports for YOUR live listing (dungeon/key source).
    local li = NS.CurrentListingInfo and NS.CurrentListingInfo() or {}
    print(string.format("|cffff2020[LFGAlert]|r listing: title=\"%s\" key=%s dungeon=%s",
      tostring(li.title or ""), tostring(li.key), tostring(li.dungeon or "-")))
    print("  full: " .. tostring(li.dungeonFull))
    if C_LFGList and C_LFGList.GetActiveEntryInfo then
      local ok, e = pcall(C_LFGList.GetActiveEntryInfo)
      if ok and e then
        local acts
        if type(e.activityIDs) == "table" then
          local t = {}
          for _, v in ipairs(e.activityIDs) do t[#t + 1] = tostring(v) end
          acts = table.concat(t, ",")
        else
          acts = tostring(e.activityIDs)
        end
        print("  raw: name=\"" .. tostring(e.name) .. "\" activityIDs=" .. acts)
        local actID = (e.activityIDs and e.activityIDs[1]) or e.activityID
        if actID and C_LFGList.GetActivityInfo then
          local r = { pcall(C_LFGList.GetActivityInfo, actID) }
          print("  activityInfo ok=" .. tostring(r[1]) .. " r2=" .. type(r[2]) .. " r3=" .. type(r[3]))
          if type(r[2]) == "table" then
            for k, v in pairs(r[2]) do print("    ." .. tostring(k) .. " = " .. tostring(v)) end
          else
            print("  values: " .. tostring(r[2]) .. " | " .. tostring(r[3]))
          end
        end
      else
        print("  no active listing entry right now (list a group first)")
      end
    end
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel then
      local _, lvl = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
      local _, mapID = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
      print("  ownedKey: lvl=" .. tostring(lvl) .. " mapID=" .. tostring(mapID))
      if mapID then
        for _, fn in ipairs({ "GetMapInfo", "GetMapUIInfo" }) do
          local f = C_ChallengeMode and C_ChallengeMode[fn]
          if type(f) == "function" then
            local ok, a = pcall(f, mapID)
            print("    C_ChallengeMode." .. fn .. ": ok=" .. tostring(ok) .. " name=" .. tostring(a))
          else
            print("    C_ChallengeMode." .. fn .. ": MISSING")
          end
        end
      end
    else
      print("  ownedKey: C_MythicPlus API missing")
    end
  elseif cmd == "autodecline" or cmd == "ad" then
    -- Uses minIlvl/minScore thresholds; never fires without real data.
    if rest == "on" then NS.db.autoDecline = true
    elseif rest == "off" then NS.db.autoDecline = false
    else NS.db.autoDecline = not NS.db.autoDecline end
    print(string.format("|cffff2020[LFGAlert]|r Auto-decline %s (min ilvl %s, min M+ %s)",
      NS.db.autoDecline and "ON" or "OFF",
      (NS.db.minIlvl or 0) > 0 and tostring(NS.db.minIlvl) or "off",
      (NS.db.minScore or 0) > 0 and tostring(NS.db.minScore) or "off"))
  elseif cmd == "stats" then
    NS.PrintStats()
  elseif cmd == "debug" then
    local log = NS.Data().log or {}
    local fst = (NS.logFilter and NS.logFilter.status) or "?"
    local q = (NS.logFilter and NS.logFilter.query) or ""
    print(string.format("|cffff2020[LFGAlert]|r debug [build %s]: %d stored, filter=%s search=\"%s\"",
      tostring(NS.BUILD), #log, fst, q))
    for i = math.max(1, #log - 4), #log do
      local e = log[i]
      if e and e.separator then
        print("  [" .. i .. "] --- " .. tostring(e.separator))
      elseif e then
        local nm = (e.members and e.members[1] and e.members[1].name) or "?"
        print(string.format("  [%d] id=%s status=%s members=%d name=%s",
          i, tostring(e.applicantID), tostring(e.status), #(e.members or {}), tostring(nm)))
      end
    end
    if NS.ToggleLogUI then NS.ToggleLogUI(true) end
    if NS.GetLogUIState then
      local st = NS.GetLogUIState()
      print(string.format("  window: built=%s shown=%s visibleRows=%d scroll=%d bg=%s",
        tostring(st.built), tostring(st.shown), st.visibleRows or 0, st.scrollOffset or 0,
        tostring(NS._bgMode or "?")))
    end
    if NS.ProbeLogUI then
      local p = NS.ProbeLogUI()
      print(string.format("  probe: pool=%s built=%s r1=%s shown=%s hasEntry=%s emptyCols=%s renderOK=%s",
        tostring(p.pool), tostring(p.built), tostring(p.r1), tostring(p.shown), tostring(p.hasEntry),
        tostring(p.emptyCols), tostring(p.renderOK)))
      print(string.format("  box: cont=%sx%s contVis=%s row1Y=%s r1w=%s",
        tostring(p.contW), tostring(p.contH), tostring(p.contVis),
        tostring(p.row1Y), tostring(p.r1w)))
      print(string.format("  vis: frame=%s r1=%s",
        tostring(p.frameVis), tostring(p.r1vis)))
      if p.firstText then print("  firstText: " .. tostring(p.firstText)) end
      if p.renderErr then print("  renderErr: " .. tostring(p.renderErr)) end
    end
    if NS._rowBuildError then print("  buildError: " .. tostring(NS._rowBuildError)) end
    do
      local ar = NS.db and NS.db.alertRoles
      local function g(ch, role)
        local c = ar and ar[ch]
        if c == nil then return "on" end
        local v = c[role]
        if v == nil then return "on" end
        return v and "on" or "OFF"
      end
      print(string.format("  gates: sound T/H/D=%s/%s/%s chat=%s/%s/%s screen=%s/%s/%s popup=%s/%s/%s",
        g("sound", "TANK"), g("sound", "HEALER"), g("sound", "DAMAGER"),
        g("chat", "TANK"), g("chat", "HEALER"), g("chat", "DAMAGER"),
        g("screen", "TANK"), g("screen", "HEALER"), g("screen", "DAMAGER"),
        g("popup", "TANK"), g("popup", "HEALER"), g("popup", "DAMAGER")))
    end
    if NS._lastRenderError then print("  lastRenderError: " .. tostring(NS._lastRenderError)) end
    if NS._buildErrors then
      for _, be in ipairs(NS._buildErrors) do print("  buildError: " .. tostring(be)) end
    end
  elseif cmd == "on" then
    NS.db.enabled = true
    print("|cffff2020[LFGAlert]|r Enabled.")
  elseif cmd == "off" then
    NS.db.enabled = false
    print("|cffff2020[LFGAlert]|r Disabled.")
  elseif cmd == "export" then
    print("|cffffcc00[LFGAlert] settings string (copy the green line):|r")
    print("|cff00ff00" .. NS.ExportSettings() .. "|r")
  elseif cmd == "import" then
    if rest == "" then
      print("|cffff2020[LFGAlert]|r Usage: /lfgalert import <green string from /lfgalert export>")
    else
      local n = NS.ImportSettings(rest)
      print(string.format("|cffff2020[LFGAlert]|r Imported %d settings. (/reload not needed.)", n))
      if NS.RefreshLogUI then NS.RefreshLogUI(true) end
    end
  else
    print("|cffffcc00LFGAlert commands:|r")
    print("  /lfgalert show|hide|toggle - applicant log window")
    print("  /lfgalert config - open settings")
    print("  /lfgalert clear - wipe log history")
    print("  /lfgalert test - test sound + add sample row")
    print("  /lfgalert sound [<id>] - toggle or set sound ID (default 8959)")
    print("  /lfgalert rolesound tank|healer|dps <id>|off - per-role sound")
    print("  /lfgalert soundfile <path>|off - custom sound file (e.g. Interface\\AddOns\\LFGAlert\\Sounds\\alert.ogg)")
    print("  /lfgalert minilvl <n> - highlight min item level (0 = off)")
    print("  /lfgalert minscore <n> - highlight min M+ score (0 = off)")
    print("  /lfgalert autodecline [on|off] - auto-decline below thresholds (default OFF)")
    print("  /lfgalert filter <all|queued|invited|accepted|declined|gone> - filter log")
    print("  /lfgalert class <name|all> - filter by class")
    print("  /lfgalert minkey <n> - only keys >= n (0 = all)")
    print("  /lfgalert window [on|off] - auto-open Group Finder applicants on queue")
    print("  /lfgalert open - open Group Finder applicants now")
    print("  /lfgalert mute [on|off] - master mute for sound/chat/screen/popup")
    print("  /lfgalert groupbykey [on|off] - group log rows under their key")
    print("  /lfgalert export|import - share or restore your settings")
    print("  /lfgalert rolesoundfile tank|healer|dps <path>|off - per-role sound file")
    print("  /lfgalert resetui - reset log window position / size / scale")
    print("  /lfgalert stats - session + all-time summary")
    print("  /lfgalert debug - dump log state (entries/filter/window)")
    print("  /lfgalert mouse - report which frame is under the mouse")
    print("  /lfgalert listing - dump your live listing (dungeon/key source)")
    print("  /lfgalert on|off - enable/disable alerts")
  end
end

-- ---------------------------------------------------------------------------
-- Settings export / import: every scalar option as one shareable string.
-- The log and stats are NOT included (per-account data). Slash input arrives
-- lowercased, so exported strings are lowercase-safe by construction
-- (file paths are case-insensitive in WoW).
-- ---------------------------------------------------------------------------

local EXPORT_SCALARS = {
  { "soundEnabled", "b" }, { "soundID", "n" }, { "useCustomSound", "b" },
  { "customSoundPath", "s" }, { "useMasterChannel", "b" },
  { "raidWarning", "b" }, { "chatMessage", "b" }, { "flashTaskbar", "b" },
  { "autoOpenLFG", "b" }, { "assumeOwnKey", "b" },
  { "minIlvl", "n" }, { "minScore", "n" }, { "autoDecline", "b" },
  { "maxLogEntries", "n" }, { "showMinimapButton", "b" }, { "minimapAngle", "n" },
  { "muteAll", "b" }, { "statsSummary", "b" }, { "perCharLog", "b" },
  { "groupByKey", "b" }, { "enabled", "b" },
}

function NS.ExportSettings()
  local parts = {}
  local function add(k, v, t)
    if v == nil then return end
    if t == "b" then
      parts[#parts + 1] = k .. "=" .. (v and "1" or "0")
    elseif t == "n" then
      parts[#parts + 1] = k .. "=" .. tostring(v)
    else
      parts[#parts + 1] = k .. "=" .. tostring(v):lower():gsub(";", ",")
    end
  end
  for _, sc in ipairs(EXPORT_SCALARS) do add(sc[1], NS.db[sc[1]], sc[2]) end
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    add("rs." .. role, NS.db.roleSounds and NS.db.roleSounds[role], "n")
    add("rsf." .. role, NS.db.roleSoundFiles and NS.db.roleSoundFiles[role], "s")
    for _, chan in ipairs({ "sound", "chat", "screen", "popup" }) do
      local gates = NS.db.alertRoles and NS.db.alertRoles[chan]
      add("g." .. chan .. "." .. role, gates and gates[role], "b")
    end
  end
  return table.concat(parts, ";")
end

function NS.ImportSettings(str)
  local applied = 0
  local byName = {}
  for _, sc in ipairs(EXPORT_SCALARS) do byName[sc[1]] = sc[2] end
  for pair in tostring(str or ""):gmatch("[^;]+") do
    local k, v = pair:match("^(%S+)=(.*)$")
    if k and v then
      local role, chan
      if k:match("^rs%.") then
        role = k:match("^rs%.(%a+)")
        NS.db.roleSounds = NS.db.roleSounds or {}
        local num = tonumber(v)
        if role then
          if num and num > 0 then NS.db.roleSounds[role] = num else NS.db.roleSounds[role] = nil end
          applied = applied + 1
        end
      elseif k:match("^rsf%.") then
        role = k:match("^rsf%.(%a+)")
        NS.db.roleSoundFiles = NS.db.roleSoundFiles or {}
        if role then
          NS.db.roleSoundFiles[role] = (v ~= "" and v ~= "off") and v or ""
          applied = applied + 1
        end
      elseif k:match("^g%.") then
        chan, role = k:match("^g%.(%a+)%.(%a+)")
        if chan and role then
          NS.db.alertRoles = NS.db.alertRoles or {}
          NS.db.alertRoles[chan] = NS.db.alertRoles[chan] or {}
          NS.db.alertRoles[chan][role] = (v == "1" or v == "true")
          applied = applied + 1
        end
      else
        local t = byName[k]
        if t == "b" then
          NS.db[k] = (v == "1" or v == "true")
          applied = applied + 1
        elseif t == "n" then
          local num = tonumber(v)
          if num then NS.db[k] = num; applied = applied + 1 end
        elseif t == "s" then
          NS.db[k] = v
          applied = applied + 1
        end
      end
    end
  end
  return applied
end

