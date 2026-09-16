-- LFGAlert - Core.lua
-- Sound alert + applicant tracking for your Premade Group (Group Finder) listing.
-- Retail / Midnight (12.x). Lightweight, no dependencies. Optional Raider.IO support.
--
-- What it does (like [Top] Party Alarm, plus more):
--   * Plays a sound + raid-warning + chat message when someone applies
--   * Keeps a log: queued / invited / accepted / declined / cancelled / timeout
--   * Stores class, spec, item level, M+ score (Blizzard dungeonScore + Raider.IO if installed)
--   * Right-click a log row to whisper / invite / decline

local ADDON_NAME = ...
LFGAlert = LFGAlert or {}
local NS = LFGAlert
local L = NS.L or {} -- from Locales\enUS.lua (loaded first per .toc)
local function l(key, fallback) return L[key] or fallback end
NS.BUILD = 17 -- bump every shipment; shown in load message + /lfgalert debug

-- ---------------------------------------------------------------------------
-- Defaults / DB
-- ---------------------------------------------------------------------------

local DEFAULTS = {
  enabled = true,
  soundEnabled = true,
  -- SOUNDKIT id. RAID_WARNING = 8959. Change via /lfgalert sound <id>
  soundID = 8959,
  -- Custom sound file (optional). Example: "Interface\\AddOns\\LFGAlert\\Sounds\\alert.ogg"
  -- or a file path via /lfgalert soundfile <path>. Takes precedence when enabled.
  useCustomSound = false,
  customSoundPath = "",
  useMasterChannel = true,
  raidWarning = true,
  chatMessage = true,
  flashTaskbar = true,
  showMinimapButton = true,
  minimapAngle = 220,
  maxLogEntries = 300,
  -- Highlight rules (0 = off). Rows at/above both thresholds get a star + green numbers.
  minIlvl = 0,
  minScore = 0,
  -- Pop open Blizzard's Group Finder on the applicant list when someone queues.
  autoOpenLFG = true,
  -- Midnight hides listing text from addons: fall back to your own keystone
  -- for dungeon/key when nothing readable is found (M+ own-key case).
  assumeOwnKey = true,
  -- Auto-decline applicants below minIlvl/minScore (default OFF).
  autoDecline = false,
  stats = { sessions = {}, total = { queued = 0, invited = 0, accepted = 0, declined = 0, auto = 0, gone = 0 } },
  log = {}, -- persisted entries
}

local function CopyDefaults(src)
  local t = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      t[k] = CopyDefaults(v)
    else
      t[k] = v
    end
  end
  return t
end

local function InitDB()
  if type(LFGAlertDB) ~= "table" then
    LFGAlertDB = CopyDefaults(DEFAULTS)
  else
    for k, v in pairs(DEFAULTS) do
      if LFGAlertDB[k] == nil then
        if type(v) == "table" then
          LFGAlertDB[k] = CopyDefaults(v)
        else
          LFGAlertDB[k] = v
        end
      end
    end
  end
  NS.db = LFGAlertDB
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function HasActiveListing()
  if not C_LFGList or not C_LFGList.GetActiveEntryInfo then return false end
  local ok, info = pcall(C_LFGList.GetActiveEntryInfo)
  if not ok then return false end
  return info ~= nil
end

local function IsGroupLeader()
  -- Top Party Alarm behaviour: only alert as leader. If solo with a listing,
  -- UnitIsGroupLeader returns false, so also allow "has listing but not in group".
  if not IsInGroup() then return HasActiveListing() end
  local ok, res = pcall(UnitIsGroupLeader, "player")
  if ok and res then return true end
  -- Assistants with listing? Be permissive: anyone with an active listing.
  return HasActiveListing()
end

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
NS.ClassColorize = ClassColorize

local function GetSpecName(specID)
  if not specID or specID == 0 then return nil end
  local ok, _, name = pcall(GetSpecializationInfoByID, specID)
  if ok and name and name ~= "" then return name end
  return nil
end

-- Try Raider.IO addon if present. Different RIO versions expose different APIs,
-- so probe carefully and never error. Pass a memo table to avoid re-probing the
-- same name many times within one scan (group applications multiply this).
local function GetRaiderIOScore(fullName, memo)
  if not fullName or not _G.RaiderIO then return nil end
  if memo then
    local cached = memo[fullName]
    if cached ~= nil then return cached or nil end
  end
  local score
  local RIO = _G.RaiderIO
  -- Modern RIO: RaiderIO.GetScore(unitName)
  if type(RIO.GetScore) == "function" then
    local ok, s1, s2 = pcall(RIO.GetScore, fullName)
    if ok then
      if type(s1) == "number" and s1 > 0 then score = math.floor(s1) end
      if not score and type(s2) == "number" and s2 > 0 then score = math.floor(s2) end
    end
  end
  -- Older RIO: RaiderIO.GetProfile(name, realm)
  if not score and type(RIO.GetProfile) == "function" then
    local bare, realm = strsplit("-", fullName, 2)
    local ok, profile = pcall(RIO.GetProfile, bare, realm or GetRealmName())
    if ok and type(profile) == "table" then
      local s = profile.mythicPlusScoresBySeason
        and profile.mythicPlusScoresBySeason[1]
        and profile.mythicPlusScoresBySeason[1].scores
        and profile.mythicPlusScoresBySeason[1].scores.all
      if type(s) == "number" and s > 0 then score = math.floor(s) end
      if not score and type(profile.mplusCurrentScore) == "number" and profile.mplusCurrentScore > 0 then
        score = math.floor(profile.mplusCurrentScore)
      end
    end
  end
  if memo then memo[fullName] = score or false end
  return score
end

local function FormatScore(blizzScore, rioScore)
  rioScore = rioScore and rioScore > 0 and rioScore or nil
  blizzScore = blizzScore and blizzScore > 0 and blizzScore or nil
  local base = rioScore or blizzScore
  if not base then return "-" end
  -- If both exist and differ, show RIO with Blizzard in parens on tooltip; row shows RIO.
  return tostring(base)
end

-- ---------------------------------------------------------------------------
-- Listing context: which dungeon + key level is this applicant queueing for?
-- Captured live at log time (activities + "+N" parsed from your listing title).
-- ---------------------------------------------------------------------------

-- First-letter abbreviation: "Altar of Fangs" -> "AOF", "Necrotic Wake" -> "NW".
-- Single-word names use the first 3 letters ("Freehold" -> "FRE").
local function AbbrevDungeonName(name)
  if not name or name == "" then return nil end
  local base = name:gsub("%s*%([^%)]*%)%s*", ""):gsub("^%s*[Tt]he%s+", "")
  local words = {}
  for w in base:gmatch("[%a]+") do words[#words + 1] = w end
  if #words == 0 then return nil end
  if #words == 1 then
    return words[1]:sub(1, 3):upper()
  end
  local ab = ""
  for _, w in ipairs(words) do ab = ab .. w:sub(1, 1):upper() end
  return ab ~= "" and ab or nil
end

local function ParseKeyLevel(text)
  if not text or text == "" then return nil end
  local patterns = { "%+(%d+)", "[Mm]%+%s*(%d+)", "[Mm]%s+(%d+)", "(%d+)%s*%+" }
  for _, pat in ipairs(patterns) do
    local n = tonumber(text:match(pat))
    if n and n >= 2 and n <= 40 then return n end
  end
  return nil
end

-- Midnight wraps listing/applicant text in kstrings ("|Ku5|k") that addons
-- cannot read. Strip those tokens so we never display or parse garbage.
local function CleanKString(s)
  if type(s) ~= "string" then return s end
  local cleaned = s:gsub("|K.-|k", "")
  if cleaned:match("^%s*$") then return "" end
  return cleaned
end

-- Dungeon name for a challenge (keystone) mapID. Tries each known lookup;
-- returns name + which function worked (for /lfgalert listing diagnostics).
local function GetChallengeMapName(mapID)
  if not mapID or not C_ChallengeMode then return nil end
  for _, fn in ipairs({ "GetMapInfo", "GetMapUIInfo" }) do
    local f = C_ChallengeMode[fn]
    if type(f) == "function" then
      local ok, name = pcall(f, mapID)
      if ok and type(name) == "string" and name ~= "" then return name, fn end
    end
  end
  return nil
end

-- Leader's own keystone: the fallback source when Blizzard hides the listing
-- text (the common M+ case is pushing your own key).
local function GetOwnedKeystone()
  if not (C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneChallengeMapID) then
    return nil
  end
  local okL, lvl = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
  local okM, mapID = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
  if not (okL and okM and lvl and mapID and lvl >= 2) then return nil end
  local full = GetChallengeMapName(mapID)
  return { key = lvl, dungeonFull = full, dungeon = full and AbbrevDungeonName(full) or nil, source = "keystone" }
end

-- { dungeon="AOF", dungeonFull="Altar of Fangs", key=5, title="Hunter: +5 AOF" }
function NS.CurrentListingInfo()
  local info = { dungeon = nil, dungeonFull = nil, key = nil, title = nil, source = nil }
  if not (C_LFGList and C_LFGList.GetActiveEntryInfo) then return info end
  local ok, entry = pcall(C_LFGList.GetActiveEntryInfo)
  if not ok or not entry then return info end
  local cleanTitle = CleanKString(entry.name or "")
  info.title = cleanTitle
  local actID = (entry.activityIDs and entry.activityIDs[1]) or entry.activityID
  if actID and C_LFGList.GetActivityInfo then
    local okA, full, short = pcall(C_LFGList.GetActivityInfo, actID)
    if okA and full then
      if type(full) == "table" then
        -- Struct-shaped return: pick known name fields defensively.
        local fn = full.fullName or full.name
        local sn = full.shortName or full.short
        if type(fn) == "string" and fn ~= "" then
          info.dungeonFull = fn
          info.dungeon = (type(sn) == "string" and sn ~= "" and #sn <= 12 and sn)
            or AbbrevDungeonName(fn) or fn
        end
      elseif type(full) == "string" and full ~= "" then
        info.dungeonFull = full
        if type(short) == "string" and short ~= "" and #short <= 12 then
          info.dungeon = short
        else
          info.dungeon = AbbrevDungeonName(full) or full
        end
      end
    end
  end
  info.key = ParseKeyLevel(cleanTitle .. " " .. CleanKString(entry.comment or ""))
  if info.dungeon == nil and info.key == nil and NS.db ~= nil and NS.db.assumeOwnKey ~= false then
    local ks = GetOwnedKeystone()
    if ks then
      info.dungeon, info.dungeonFull, info.key, info.source = ks.dungeon, ks.dungeonFull, ks.key, ks.source
    end
  end
  return info
end

-- ---------------------------------------------------------------------------
-- Applicant snapshot
-- ---------------------------------------------------------------------------

-- known[applicantID] = { status = "applied", time = ..., members = {...}, comment = "..." }
local known = {}
NS._known = known
-- Listing session: applicantIDs reset on every delist/relist, so stamp entries
-- to never mix data across listings. The UI uses this to refuse acting on
-- stale applicantIDs from previous listings (they can be reused by Blizzard).
local listingSession = 1
local hadListing = false

function NS.CurrentListingSession()
  return listingSession
end

local function SnapshotApplicant(applicantID, cachedListing, rioMemo)
  local infoOk, appInfo = pcall(C_LFGList.GetApplicantInfo, applicantID)
  if not infoOk or not appInfo then return nil end

  local members = {}
  local numMembers = appInfo.numMembers or 1
  for i = 1, numMembers do
    local mOk, name, class, locClass, level, itemLevel, honorLevel,
      tank, healer, damage, assignedRole, relationship,
      dungeonScore, pvpItemLevel, factionGroup, raceID, specID, isLeaver =
      pcall(C_LFGList.GetApplicantMemberInfo, applicantID, i)
    -- pcall returns ok + all returns; if ok is true, name is first real return.
    -- NOTE: member data is often not ready on the first event (nil returns);
    -- callers retry + backfill, so just skip silently here.
    if mOk and name and type(name) == "string" then
      -- Group applications sometimes return garbage specIDs; only accept sane ones.
      local saneSpec = (type(specID) == "number" and specID > 0 and specID < 10000) and specID or 0
      local specName = GetSpecName(saneSpec)
      local rio = GetRaiderIOScore(name, rioMemo)
      members[#members + 1] = {
        name = name, -- "Name-Realm"
        class = class, -- "WARRIOR"
        localizedClass = locClass,
        level = level,
        itemLevel = itemLevel or 0,
        dungeonScore = dungeonScore or 0,
        rioScore = rio or 0,
        specID = saneSpec,
        specName = specName,
        role = assignedRole,
        tank = tank, healer = healer, damage = damage,
      }
    end
  end

  return {
    status = appInfo.applicationStatus,
    numMembers = numMembers,
    comment = CleanKString(appInfo.comment) or "",
    isNew = appInfo.isNew,
    members = members,
    -- Same listing applies to every applicant in one scan: pass it in to
    -- avoid one GetActivityInfo/keystone lookup per applicant.
    listing = cachedListing or NS.CurrentListingInfo(),
  }
end

local function PrimaryMember(snap)
  if snap and snap.members and snap.members[1] then
    return snap.members[1]
  end
  return nil
end

local function ShortName(fullName)
  if not fullName then return "?" end
  local bare = strsplit("-", fullName, 2)
  return bare or fullName
end
NS.ShortName = ShortName

local function MemberSummary(snap)
  local m = PrimaryMember(snap)
  if not m then return "?  -  ilvl -  -  M+ -" end
  local classCol = ClassColorize(m.class, ShortName(m.name))
  local roleTag = NS.RoleTag(NS.ResolveRole(m))
  local specTxt = m.specName or m.localizedClass or m.class or ""
  local ilvl = (m.itemLevel and m.itemLevel > 0) and tostring(math.floor(m.itemLevel)) or "-"
  local score = FormatScore(m.dungeonScore, m.rioScore)
  local extra = ""
  if (snap.numMembers or 1) > 1 then
    extra = " (+" .. ((snap.numMembers or 1) - 1) .. ")"
  end
  local runTag = ""
  local li = snap and snap.listing
  if li and (li.dungeon or li.key) then
    runTag = "  |cffffd100[" .. (li.key and ("+" .. li.key .. " ") or "") .. (li.dungeon or "?") .. "]|r"
  end
  return string.format("%s%s  %s  %s  ilvl %s  M+ %s%s", classCol, extra, roleTag, specTxt, ilvl, score, runTag)
end

-- ---------------------------------------------------------------------------
-- Status labels
-- ---------------------------------------------------------------------------

local STATUS_META = {
  applied        = { label = l("st_applied", "QUEUED"),    color = "ffd100" }, -- gold
  invited        = { label = l("st_invited", "INVITED"),   color = "5599ff" }, -- blue
  inviteaccepted = { label = l("st_inviteaccepted", "ACCEPTED"),  color = "33cc33" }, -- green
  declined       = { label = l("st_declined", "DECLINED"), color = "ff4444" },
  declined_full  = { label = l("st_declined_full", "DECLINED (FULL)"), color = "ff4444" },
  declined_delisted = { label = l("st_declined_delisted", "DECLINED (DELISTED)"), color = "ff4444" },
  cancelled      = { label = l("st_cancelled", "CANCELLED"), color = "999999" },
  timedout       = { label = l("st_timedout", "TIMEOUT"),   color = "ff8800" },
  failed         = { label = l("st_failed", "FAILED"),      color = "ff4444" },
  invitedeclined = { label = l("st_invitedeclined", "DECLINED INVITE"), color = "ff8844" },
}

function NS.StatusLabel(status)
  local m = STATUS_META[status]
  if m then return m.label, m.color end
  return (status or "UNKNOWN"):upper(), "ffffff"
end

-- ---------------------------------------------------------------------------
-- Roles (Tank / Healer / DPS)
-- ---------------------------------------------------------------------------

function NS.ResolveRole(mem)
  if mem then
    if mem.role and mem.role ~= "" then return (mem.role .. ""):upper() end
    if mem.tank then return "TANK" end
    if mem.healer then return "HEALER" end
    if mem.damage then return "DAMAGER" end
  end
  return nil
end

-- Returns coloredTag, plainLabel. Role icons resolve lazily via _G so this
-- is safe even when Blizzard's UI addons haven't loaded yet (falls back to text).
function NS.RoleTag(role)
  local key = role and (role .. ""):upper() or ""
  local label, color, iconKey = "—", "aaaaaa", nil
  if key == "TANK" then
    label, color, iconKey = l("role_tank", "Tank"), "5b9bff", "INLINE_TANK_ICON"
  elseif key == "HEALER" then
    label, color, iconKey = l("role_healer", "Heal"), "4dff4d", "INLINE_HEALER_ICON"
  elseif key == "DAMAGER" then
    label, color, iconKey = l("role_dps", "DPS"), "ff6b6b", "INLINE_DAMAGER_ICON"
  end
  local icon = (iconKey and _G[iconKey]) or ""
  if icon ~= "" then icon = icon .. " " end
  return icon .. "|cff" .. color .. label .. "|r", label
end

-- ---------------------------------------------------------------------------
-- Log (persisted) - UI lives in LogFrame.lua
-- ---------------------------------------------------------------------------

local function TrimLog()
  local maxN = (NS.db and NS.db.maxLogEntries) or 300
  while #NS.db.log > maxN do
    table.remove(NS.db.log, 1)
  end
end

local function SnapHasData(snap)
  return snap and snap.members and snap.members[1]
    and type(snap.members[1].name) == "string" and true or false
end

local function CopySnapMembers(dest, snap)
  if not (snap and snap.members) then return end
  for i, mem in ipairs(snap.members) do
    dest[i] = {
      name = mem.name,
      class = mem.class,
      localizedClass = mem.localizedClass,
      specName = mem.specName,
      level = mem.level,
      itemLevel = mem.itemLevel,
      dungeonScore = mem.dungeonScore,
      rioScore = mem.rioScore,
      role = mem.role,
    }
    if i >= 8 then break end -- cap stored group size
  end
end

-- ---------------------------------------------------------------------------
-- Statistics: every status transition funnels through AddLogEntry, so count
-- it here. Sessions are keyed by listingSession; only the last 30 are kept.
-- ---------------------------------------------------------------------------

local autoPending = {} -- applicantID -> true while OUR auto-decline is in flight

local function BucketFor(status)
  if status == "applied" then return "queued" end
  if status == "invited" then return "invited" end
  if status == "inviteaccepted" then return "accepted" end
  if status == "cancelled" or status == "timedout" then return "gone" end
  return "declined" -- declined, declined_full, declined_delisted, failed, invitedeclined
end

local function EnsureStats()
  if type(LFGAlertDB) ~= "table" then return nil end
  NS.db = NS.db or LFGAlertDB
  if type(NS.db.stats) ~= "table" then
    NS.db.stats = { sessions = {}, total = { queued = 0, invited = 0, accepted = 0, declined = 0, auto = 0, gone = 0 } }
  end
  if type(NS.db.stats.sessions) ~= "table" then NS.db.stats.sessions = {} end
  if type(NS.db.stats.total) ~= "table" then
    NS.db.stats.total = { queued = 0, invited = 0, accepted = 0, declined = 0, auto = 0, gone = 0 }
  end
  return NS.db.stats
end

function NS.RecordStat(applicantID, status, session)
  if not applicantID or applicantID == 0 then return end -- skip test rows
  local st = EnsureStats()
  if not st then return end
  local bucket = BucketFor(status)
  if bucket == "declined" and autoPending[applicantID] then
    autoPending[applicantID] = nil
    bucket = "auto"
  end
  session = session or listingSession
  local sess = st.sessions[session]
  if not sess then
    sess = { queued = 0, invited = 0, accepted = 0, declined = 0, auto = 0, gone = 0, started = time() }
    st.sessions[session] = sess
    -- Cap stored sessions at 30 (drop oldest).
    local n = 0
    for _ in pairs(st.sessions) do n = n + 1 end
    while n > 30 do
      local oldest, oldestKey = nil, nil
      for k, v in pairs(st.sessions) do
        if oldest == nil or (v.started or 0) < oldest then oldest, oldestKey = (v.started or 0), k end
      end
      if oldestKey == nil then break end
      st.sessions[oldestKey] = nil
      n = n - 1
    end
  end
  sess[bucket] = (sess[bucket] or 0) + 1
  st.total[bucket] = (st.total[bucket] or 0) + 1
end

local function StatLine(label, s)
  s = s or {}
  local q, a, d, au = s.queued or 0, s.accepted or 0, s.declined or 0, s.auto or 0
  local rate = q > 0 and math.floor(a / q * 100 + 0.5) or 0
  local autoTxt = au > 0 and l("stats_auto_paren", " (%d auto)"):format(au) or ""
  return l("stats_line_fmt", "%s: %d queued • %d accepted (%d%%) • %d declined%s • %d invited • %d left")
    :format(label, q, a, rate, d + au, autoTxt, s.invited or 0, s.gone or 0)
end

function NS.PrintStats()
  local st = EnsureStats()
  if not st then return end
  print("|cffffcc00" .. l("stats_header", "LFGAlert stats:") .. "|r")
  local cur = st.sessions[listingSession]
  if cur and (cur.queued or 0) > 0 then
    print("  " .. StatLine(l("this_listing", "This listing"), cur))
  else
    print("  " .. l("this_listing_none", "This listing: no queues yet"))
  end
  print("  " .. StatLine(l("all_time", "All time"), st.total))
  -- Accepted quality averages from stored log rows.
  local n, ilvlSum, scoreSum, scoreN = 0, 0, 0, 0
  for _, e in ipairs((NS.db and NS.db.log) or {}) do
    if not e.separator and e.status == "inviteaccepted" and e.members and e.members[1] and e.members[1].name then
      local m = e.members[1]
      n = n + 1
      ilvlSum = ilvlSum + (m.itemLevel or 0)
      local sc = NS.EffectiveScore(m)
      if sc > 0 then scoreSum, scoreN = scoreSum + sc, scoreN + 1 end
    end
  end
  if n > 0 then
    local scTxt = scoreN > 0 and l("stats_avg_score", " M+ %d"):format(math.floor(scoreSum / scoreN + 0.5)) or ""
    print(l("stats_avg_fmt", "  Accepted avg (n=%d): ilvl %d%s"):format(n, math.floor(ilvlSum / n + 0.5), scTxt))
  end
end

function NS.AddLogEntry(applicantID, oldStatus, newStatus, snap, isNewApplicant)
  NS.db = NS.db or LFGAlertDB
  if not NS.db then return end
  local m = PrimaryMember(snap)
  local li = (snap and snap.listing) or NS.CurrentListingInfo()

  -- One row per applicant per listing session: a status transition UPDATES
  -- the existing row (shown as lifecycle icons in the log) instead of
  -- stacking separate "Queued" / "Invited" / "Accepted" rows.
  local entry
  for i = #NS.db.log, 1, -1 do
    local e = NS.db.log[i]
    if e and not e.separator and e.applicantID == applicantID
      and (e.session == nil or e.session == listingSession) then
      entry = e
      break
    end
  end

  local now = time()
  if entry then
    entry.oldStatus = oldStatus
    entry.status = newStatus
    -- A (re-)application surfaces the row as fresh again.
    if newStatus == "applied" then entry.t = now end
    if SnapHasData(snap) then
      wipe(entry.members)
      CopySnapMembers(entry.members, snap)
    end
    entry.numMembers = (snap and snap.numMembers) or entry.numMembers or 1
    if snap and snap.comment and snap.comment ~= "" then entry.comment = snap.comment end
    if entry.dungeon == nil and li then
      entry.dungeon, entry.dungeonFull, entry.key, entry.keySource, entry.listingTitle =
        li.dungeon, li.dungeonFull, li.key, li.source, li.title
    end
    entry.history = entry.history or {}
    entry.history[#entry.history + 1] = { status = newStatus, t = now }
    if #entry.history > 8 then table.remove(entry.history, 1) end
  else
    entry = {
      t = now,
      applicantID = applicantID,
      oldStatus = oldStatus,
      status = newStatus,
      isNew = isNewApplicant and true or false,
      comment = (snap and snap.comment) or "",
      numMembers = (snap and snap.numMembers) or (m and 1) or 1,
      members = {},
      detailShown = SnapHasData(snap),
      dungeon = li and li.dungeon or nil,
      dungeonFull = li and li.dungeonFull or nil,
      key = li and li.key or nil,
      keySource = li and li.source or nil,
      listingTitle = li and li.title or nil,
      session = listingSession,
      history = { { status = newStatus, t = now } },
    }
    CopySnapMembers(entry.members, snap)
    NS.db.log[#NS.db.log + 1] = entry
  end
  if BucketFor(newStatus) == "declined" and NS._autoReason then
    local ar = NS._autoReason[applicantID]
    if ar and (ar.session == nil or ar.session == listingSession) then
      entry.declineReason = ar.text or "Auto"
      entry.autoDeclined = true
    end
    NS._autoReason[applicantID] = nil
  end
  TrimLog()
  NS.RecordStat(applicantID, newStatus, entry.session)
  if NS.RefreshLogUI then
    NS.RefreshLogUI()
  end
  return entry
end

function NS.ClearLog()
  if NS.db then NS.db.log = {} end
  if NS.RefreshLogUI then NS.RefreshLogUI() end
end

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------

function NS.PlayAlertSound()
  if not NS.db or not NS.db.soundEnabled then return end
  local channel = NS.db.useMasterChannel and "Master" or nil
  -- Custom sound file takes precedence when enabled and set.
  if NS.db.useCustomSound and NS.db.customSoundPath and NS.db.customSoundPath ~= "" then
    local ok, played = pcall(PlaySoundFile, NS.db.customSoundPath, channel)
    -- pcall only catches argument errors; PlaySoundFile's boolean return is
    -- the real "did it play" signal (false = missing/invalid file). nil means
    -- the client returned nothing: assume success so we never double-play.
    if ok and played ~= false then return end
    -- Fall through to SoundKit ID if the file path failed.
  end
  local id = tonumber(NS.db.soundID) or 8959
  local ok = pcall(PlaySound, id, channel)
  if not ok then
    pcall(PlaySound, 8959, channel)
  end
end

-- ---------------------------------------------------------------------------
-- Highlight thresholds
-- ---------------------------------------------------------------------------

-- Effective M+ score: prefer Raider.IO, fall back to Blizzard dungeonScore.
function NS.EffectiveScore(mem)
  if not mem then return 0 end
  if mem.rioScore and mem.rioScore > 0 then return mem.rioScore end
  return mem.dungeonScore or 0
end

-- Returns meetsIlvl, meetsScore, meetsAll. A 0 threshold means "rule off".
function NS.MeetsThresholds(mem)
  if not mem then return true, true, true end
  local minIlvl = (NS.db and NS.db.minIlvl) or 0
  local minScore = (NS.db and NS.db.minScore) or 0
  local meetsIlvl = minIlvl <= 0 or (mem.itemLevel or 0) >= minIlvl
  local meetsScore = minScore <= 0 or NS.EffectiveScore(mem) >= minScore
  return meetsIlvl, meetsScore, (meetsIlvl and meetsScore)
end

local function CenterMessage(text)
  if not NS.db or not NS.db.raidWarning then return end
  if RaidWarningFrame and RaidNotice_AddMessage then
    local ok = pcall(RaidNotice_AddMessage, RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"])
    if ok then return end
  end
  if UIErrorsFrame then
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, 0.2, 0.2, 1.0, 5)
  end
end

local function ChatMessage(text)
  if not NS.db or not NS.db.chatMessage then return end
  print("|cffff2020[LFGAlert]|r " .. text)
end

function NS.AlertNewApplicant(applicantID, snap)
  NS.PlayAlertSound()
  if NS.db and NS.db.flashTaskbar and FlashClientIcon then
    pcall(FlashClientIcon)
  end
  if NS.db and NS.db.autoOpenLFG then
    NS.OpenApplicants()
  end
  if not SnapHasData(snap) then
    -- Details not ready yet: keep the sound + a generic banner now;
    -- BackfillLogEntry prints the full line + fills the log row on retry.
    CenterMessage(l("alert_banner", "New applicant!"))
    return
  end
  local summary = MemberSummary(snap)
  local pm = PrimaryMember(snap)
  local name = pm and pm.name or ("#" .. tostring(applicantID))
  local _, rolePlain = NS.RoleTag(NS.ResolveRole(pm))
  CenterMessage(l("alert_center_fmt", "New applicant: %s (%s)"):format(ShortName(name), rolePlain))
  ChatMessage(l("alert_chat_fmt", "New applicant: %s"):format(summary))
  if snap and snap.comment and snap.comment ~= "" then
    ChatMessage(l("note_fmt", 'Note: "%s"'):format(snap.comment))
  end
end

function NS.AnnounceStatusChange(applicantID, oldStatus, newStatus, snap)
  local label, color = NS.StatusLabel(newStatus)
  local summary = MemberSummary(snap)
  ChatMessage(string.format("%s: |cff%s%s|r - %s", ShortName(PrimaryMember(snap) and PrimaryMember(snap).name or ("#" .. applicantID)), color, label, summary))
end

-- Member data is often unavailable on the first event (Blizzard sends the
-- list before the details). This fills previously-logged "?" rows once the
-- data arrives, and prints the full detail line if it was skipped earlier.
local function BackfillLogEntry(applicantID, snap)
  if not SnapHasData(snap) then return false end
  if not (NS.db and NS.db.log) then return false end
  local changed = false
  for _, e in ipairs(NS.db.log) do
    if not e.separator and e.applicantID == applicantID and (e.session == nil or e.session == listingSession) then
      local em = e.members and e.members[1]
      if not (em and em.name) then
        e.members = e.members or {}
        CopySnapMembers(e.members, snap)
        e.numMembers = snap.numMembers or e.numMembers
        if snap.comment and snap.comment ~= "" then e.comment = snap.comment end
        if e.dungeon == nil and snap.listing and snap.listing.dungeon then
          e.dungeon, e.dungeonFull, e.key, e.keySource, e.listingTitle =
            snap.listing.dungeon, snap.listing.dungeonFull, snap.listing.key, snap.listing.source, snap.listing.title
        end
        if not e.detailShown then
          e.detailShown = true
          ChatMessage(l("alert_chat_fmt", "New applicant: %s"):format(MemberSummary({ members = e.members, numMembers = e.numMembers, comment = e.comment, listing = snap.listing })))
          if e.comment and e.comment ~= "" then
            ChatMessage(l("note_fmt", 'Note: "%s"'):format(e.comment))
          end
        end
        -- MaybeAutoDecline re-verifies the applicant is still pending, so it
        -- is safe to attempt on every backfill.
        NS.MaybeAutoDecline(applicantID, snap)
        changed = true
      end
    end
  end
  if changed and NS.RefreshLogUI then NS.RefreshLogUI() end
  return changed
end
NS.BackfillLogEntry = BackfillLogEntry

-- ---------------------------------------------------------------------------
-- Auto-decline: when enabled, applicants below minIlvl/minScore are declined
-- automatically once their data is known. NEVER fires without real data.
-- Judges the primary member (the one shown in the log row).
-- ---------------------------------------------------------------------------

function NS.MaybeAutoDecline(applicantID, snap)
  if not NS.db or not NS.db.autoDecline then return false end
  if not applicantID or applicantID == 0 then return false end
  if not ((NS.db.minIlvl or 0) > 0 or (NS.db.minScore or 0) > 0) then return false end
  local m = snap and snap.members and snap.members[1]
  if not (m and m.name) then return false end -- never judge without data
  -- Re-verify still pending (leader may have invited meanwhile).
  local ok, info = pcall(C_LFGList.GetApplicantInfo, applicantID)
  if not (ok and info and info.applicationStatus == "applied") then return false end
  local reasons = {}
  local ilvlFail, scoreFail = false, false
  if (NS.db.minIlvl or 0) > 0 and (m.itemLevel or 0) > 0 and m.itemLevel < NS.db.minIlvl then
    ilvlFail = true
    reasons[#reasons + 1] = "ilvl " .. math.floor(m.itemLevel) .. " < " .. NS.db.minIlvl
  end
  if (NS.db.minScore or 0) > 0 then
    local sc = NS.EffectiveScore(m)
    if sc > 0 and sc < NS.db.minScore then
      scoreFail = true
      reasons[#reasons + 1] = "M+ " .. math.floor(sc) .. " < " .. NS.db.minScore
    end
  end
  if #reasons == 0 then return false end
  autoPending[applicantID] = true
  NS._autoReason = NS._autoReason or {}
  NS._autoReason[applicantID] = {
    text = (ilvlFail and scoreFail) and l("ar_both", "Low ILvl/M+")
      or (ilvlFail and l("ar_ilvl", "Low ILvl") or l("ar_score", "Low M+")),
    session = listingSession,
  }
  pcall(C_LFGList.DeclineApplicant, applicantID)
  ChatMessage(l("auto_declined_fmt", "Auto-declined %s (%s)"):format(ShortName(m.name), table.concat(reasons, ", ")))
  return true
end

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

-- Single funnel for "we just fetched a fresh snapshot of an applicant":
-- both the full-list scan and the per-applicant event path call this, so
-- new-applicant alerts, status-change logging and data backfill behave
-- identically everywhere.
local function HandleApplicantSnapshot(applicantID, snap, reason)
  if not snap then return end
  local prev = known[applicantID]
  if not prev then
    known[applicantID] = { status = snap.status, snap = snap }
    NS.AddLogEntry(applicantID, nil, snap.status or "applied", snap, true)
    if snap.status == "applied" then
      NS.AlertNewApplicant(applicantID, snap)
      NS.MaybeAutoDecline(applicantID, snap)
    else
      NS.AnnounceStatusChange(applicantID, nil, snap.status, snap)
    end
  elseif prev.status ~= snap.status then
    local old = prev.status
    known[applicantID] = { status = snap.status, snap = snap }
    NS.AddLogEntry(applicantID, old, snap.status, snap, false)
    NS.AnnounceStatusChange(applicantID, old, snap.status, snap)
    -- Re-alert if they re-applied after cancel/decline
    if snap.status == "applied" and reason == "list" then
      NS.PlayAlertSound()
    end
  else
    -- Same status: refresh snapshot (ilvl/score may have resolved late)
    -- and fill any "?" log rows now that data is available.
    prev.snap = snap
    BackfillLogEntry(applicantID, snap)
  end
end

local function ScanApplicants(reason, retryN)
  if not NS.db or not NS.db.enabled then return end
  if not HasActiveListing() then return end
  -- Only the leader's client should scream. (Listing exists => we listed it.)
  if not IsGroupLeader() then return end
  if not C_LFGList.GetApplicants then return end

  local ok, ids = pcall(C_LFGList.GetApplicants)
  if not ok or type(ids) ~= "table" then return end

  -- The listing is the same for every applicant in this scan: resolve it once
  -- (activity-info + keystone lookups) instead of once per applicant.
  local listing = NS.CurrentListingInfo()
  local rioMemo = {}

  local missingData = false
  for _, applicantID in ipairs(ids) do
    local snap = SnapshotApplicant(applicantID, listing, rioMemo)
    if snap then
      if not SnapHasData(snap) then missingData = true end
      HandleApplicantSnapshot(applicantID, snap, reason)
    end
  end

  -- Applicants that vanished from the API (accepted into group, expired, etc.)
  -- stay in `known` so we don't re-alert; they are already in the log history.

  -- Blizzard fires the list event before member details are queryable, so
  -- retry a few times until every visible applicant has data.
  retryN = retryN or 0
  if missingData and retryN < 4 and HasActiveListing() then
    C_Timer.After(2, function() ScanApplicants(reason, retryN + 1) end)
  end
end

function NS.Rescan(reason)
  -- Defer a moment: Blizzard often fires LIST_UPDATED before member data is ready.
  C_Timer.After(0.5, function() ScanApplicants(reason or "list", 0) end)
end

function NS.WipeKnown(reasonLabel)
  if reasonLabel then
    local st = EnsureStats()
    local s = st and st.sessions[listingSession]
    if s and (s.queued or 0) > 0 then
      ChatMessage(StatLine(l("listing_over", "Listing over"), s))
    end
  end
  wipe(known)
  wipe(autoPending)
  if NS._autoReason then wipe(NS._autoReason) end
  if reasonLabel and NS.db and NS.db.log then
    -- Visual separator in the log so sessions don't blur together.
    NS.db.log[#NS.db.log + 1] = { t = time(), separator = l("sep_ended", "— listing ended —") }
    TrimLog()
    if NS.RefreshLogUI then NS.RefreshLogUI() end
  end
end

-- ---------------------------------------------------------------------------
-- Open Blizzard's Group Finder on your applicant list
-- Uses live FrameXML entry points (Blizzard_GroupFinder/Mainline/LFGList.lua):
--   PVEFrame_ShowFrame("GroupFinderFrame") + LFGListFrame_SetActivePanel(..., ApplicationViewer)
-- ---------------------------------------------------------------------------

local pendingOpenLFG = false

function NS.OpenApplicants()
  -- Never fight the UI during combat: queue the open for when combat drops
  -- (PLAYER_REGEN_ENABLED below picks it up).
  if InCombatLockdown and InCombatLockdown() then
    pendingOpenLFG = true
    return
  end
  -- Blizzard_GroupFinder is load-on-demand in Midnight; make sure it's up.
  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_GroupFinder")
  elseif LoadAddOn then
    pcall(LoadAddOn, "Blizzard_GroupFinder")
  end
  if GroupFinderFrame and PVEFrame_ShowFrame then
    local okV, vis = pcall(GroupFinderFrame.IsVisible, GroupFinderFrame)
    if not okV or not vis then
      pcall(PVEFrame_ShowFrame, "GroupFinderFrame")
    end
  elseif PVEFrame and PVEFrame.Show then
    local okV, vis = pcall(PVEFrame.IsShown, PVEFrame)
    if not okV or not vis then
      pcall(PVEFrame.Show, PVEFrame)
    end
  end
  if LFGListFrame and LFGListFrame.ApplicationViewer and LFGListFrame_SetActivePanel then
    pcall(LFGListFrame_SetActivePanel, LFGListFrame, LFGListFrame.ApplicationViewer)
  end
end

-- ---------------------------------------------------------------------------
-- Right-click actions (called from LogFrame rows)
-- ---------------------------------------------------------------------------

function NS.Whisper(name)
  if not name or name == "" then return end
  -- Opens a /w edit box prefilled. Works cross-realm with Name-Realm.
  if ChatFrame_OpenChat then
    local frame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    pcall(ChatFrame_OpenChat, ("/w %s "):format(name), frame)
  else
    print("|cffff2020[LFGAlert]|r /w " .. name)
  end
end

function NS.InviteApplicantByID(applicantID)
  if applicantID and C_LFGList and C_LFGList.InviteApplicant then
    pcall(C_LFGList.InviteApplicant, applicantID)
  end
end

function NS.DeclineApplicantByID(applicantID)
  if applicantID and C_LFGList and C_LFGList.DeclineApplicant then
    pcall(C_LFGList.DeclineApplicant, applicantID)
  end
end

function NS.InviteByName(name)
  if not name or name == "" then return end
  -- Fallback when applicantID is gone (already declined etc.): direct invite.
  if C_PartyInfo and C_PartyInfo.InviteUnit then
    pcall(C_PartyInfo.InviteUnit, name)
  elseif InviteUnit then
    pcall(InviteUnit, name)
  end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
frame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
frame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end
    InitDB()
    -- Build each part independently: one broken part (e.g. a Blizzard
    -- template missing in a new patch) must never take down the rest,
    -- and the failure must be VISIBLE so it can be reported/fixed.
    local function SafeBuild(label, fn)
      if not fn then return end
      local ok, err = pcall(fn)
      if not ok then
        NS._buildErrors = NS._buildErrors or {}
        NS._buildErrors[#NS._buildErrors + 1] = label .. ": " .. tostring(err)
        print("|cffff2020[LFGAlert]|r " .. label .. " build error: |cffff5555" .. tostring(err) .. "|r")
      end
    end
    SafeBuild("log window", NS.BuildLogUI)
    SafeBuild("minimap button", NS.BuildMinimapButton)
    SafeBuild("settings panel", NS.BuildOptions)
    print("|cffffcc00" .. l("msg_loaded", "LFGAlert loaded (build %s). /lfgalert for log & options."):format(tostring(NS.BUILD)) .. "|r")
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    -- Open the applicant list that was deferred while in combat.
    if pendingOpenLFG then
      pendingOpenLFG = false
      NS.OpenApplicants()
    end
    return
  end

  if not NS.db or not NS.db.enabled then return end

  if event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
    NS.Rescan("list")
  elseif event == "LFG_LIST_APPLICANT_UPDATED" then
    local applicantID = ...
    if applicantID then
      C_Timer.After(0.3, function()
        if not HasActiveListing() then return end
        local snap = SnapshotApplicant(applicantID)
        if not snap then return end
        HandleApplicantSnapshot(applicantID, snap, "updated")
        if not SnapHasData(snap) then
          -- Details still not ready: retry a few times, then give up.
          local prev = known[applicantID]
          if prev then
            local n = (prev.retries or 0) + 1
            prev.retries = n
            if n <= 4 then
              C_Timer.After(2, function()
                if not HasActiveListing() then return end
                local s2 = SnapshotApplicant(applicantID)
                if s2 then
                  local p2 = known[applicantID]
                  if p2 then p2.snap = s2 end
                  BackfillLogEntry(applicantID, s2)
                end
              end)
            end
          end
        end
      end)
    else
      NS.Rescan("updated")
    end
  elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
    if HasActiveListing() then
      if not hadListing then listingSession = listingSession + 1 end
      hadListing = true
      NS.Rescan("entry")
    else
      hadListing = false
      NS.WipeKnown("— listing ended —")
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(2, function() ScanApplicants("login") end)
  end
end)

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
    CenterMessage("LFGAlert test: sound + warning OK")
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
  elseif cmd == "open" then
    NS.OpenApplicants()
  elseif cmd == "resetui" then
    if NS.ResetUI then NS.ResetUI() end
    print("|cffff2020[LFGAlert]|r Log window reset (position / size / scale).")
  elseif cmd == "config" or cmd == "options" or cmd == "settings" then
    if Settings and Settings.OpenToCategory and NS._settingsCategory then
      local okC, id = pcall(function() return NS._settingsCategory:GetID() end)
      if okC and id then pcall(Settings.OpenToCategory, id) end
    elseif InterfaceOptionsFrame_OpenToCategory then
      pcall(InterfaceOptionsFrame_OpenToCategory, "LFGAlert")
    else
      print("|cffff2020[LFGAlert]|r Open with Esc > Options > AddOns > LFGAlert")
    end
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
        local acts = "?"
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
      local okL, lvl = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
      local okM, mapID = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
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
    local log = (NS.db and NS.db.log) or {}
    local fst = (NS.logFilter and NS.logFilter.status) or "?"
    local q = (NS.logFilter and NS.logFilter.query) or ""
    print(string.format("|cffff2020[LFGAlert]|r debug [build %s]: %d stored, filter=%s search=\"%s\"", tostring(NS.BUILD), #log, fst, q))
    for i = math.max(1, #log - 4), #log do
      local e = log[i]
      if e and e.separator then
        print("  [" .. i .. "] --- " .. tostring(e.separator))
      elseif e then
        local nm = (e.members and e.members[1] and e.members[1].name) or "?"
        print(string.format("  [%d] id=%s status=%s members=%d name=%s", i, tostring(e.applicantID), tostring(e.status), #(e.members or {}), tostring(nm)))
      end
    end
    if NS.ToggleLogUI then NS.ToggleLogUI(true) end
    if NS.GetLogUIState then
      local st = NS.GetLogUIState()
      print(string.format("  window: built=%s shown=%s visibleRows=%d scroll=%d",
        tostring(st.built), tostring(st.shown), st.visibleRows or 0, st.scrollOffset or 0))
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
  else
    print("|cffffcc00LFGAlert commands:|r")
    print("  /lfgalert show|hide|toggle - applicant log window")
    print("  /lfgalert config - open settings")
    print("  /lfgalert clear - wipe log history")
    print("  /lfgalert test - test sound + add sample row")
    print("  /lfgalert sound [<id>] - toggle or set sound ID (default 8959)")
    print("  /lfgalert soundfile <path>|off - custom sound file (e.g. Interface\\AddOns\\LFGAlert\\Sounds\\alert.ogg)")
    print("  /lfgalert minilvl <n> - highlight min item level (0 = off)")
    print("  /lfgalert minscore <n> - highlight min M+ score (0 = off)")
    print("  /lfgalert autodecline [on|off] - auto-decline below thresholds (default OFF)")
    print("  /lfgalert filter <all|queued|invited|accepted|declined|gone> - filter log")
    print("  /lfgalert class <name|all> - filter by class")
    print("  /lfgalert minkey <n> - only keys >= n (0 = all)")
    print("  /lfgalert window [on|off] - auto-open Group Finder applicants on queue")
    print("  /lfgalert open - open Group Finder applicants now")
    print("  /lfgalert resetui - reset log window position / size / scale")
    print("  /lfgalert stats - session + all-time summary")
    print("  /lfgalert debug - dump log state (entries/filter/window)")
    print("  /lfgalert mouse - report which frame is under the mouse")
    print("  /lfgalert listing - dump your live listing (dungeon/key source)")
    print("  /lfgalert on|off - enable/disable alerts")
  end
end
