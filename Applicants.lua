-- LFGAlert - Applicants.lua (split from Core.lua)
LFGAlert = LFGAlert or {}
local NS = LFGAlert
local L = NS.L or {}
local function l(key, fallback) return L[key] or fallback end
local Trace = NS.Trace

local HasActiveListing = NS.HasActiveListing
local IsGroupLeader = NS.IsGroupLeader
local RoleAlertAllowed = NS.RoleAlertAllowed

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
-- Applicant snapshot
-- ---------------------------------------------------------------------------

-- known[applicantID] = { status = "applied", time = ..., members = {...}, comment = "..." }
local known = {}
NS._known = known
NS.HandleApplicantSnapshot = HandleApplicantSnapshot
NS.AdoptOrIncrementSession = AdoptOrIncrementSession
NS.CopySnapMembers = CopySnapMembers
-- Listing session: applicantIDs reset on every delist/relist, so stamp entries
-- to never mix data across listings. The UI uses this to refuse acting on
-- stale applicantIDs from previous listings (they can be reused by Blizzard).
local listingSession = 1
NS._NS._hadListing = false

function NS.CurrentListingSession()
  return listingSession
end

local function SnapshotApplicant(applicantID, cachedListing, rioMemo)
  local infoOk, appInfo = pcall(C_LFGList.GetApplicantInfo, applicantID)
  if not infoOk or not appInfo then return nil end

  local members = {}
  local numMembers = appInfo.numMembers or 1
  for i = 1, numMembers do
    local mOk, name, class, locClass, level, itemLevel, _,
      tank, healer, damage, assignedRole, _,
      dungeonScore, _, _, _, specID, _ =
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
    comment = NS.CleanKString(appInfo.comment) or "",
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

-- UTF-8 safe shortener for chat notes.
local function TruncNote(s, n)
  if not s or s == "" then return "" end
  if #s <= n then return s end
  local cut = s:sub(1, n - 1)
  cut = cut:gsub("[\194-\244][\128-\191]*$", "")
  return cut .. "..."
end

-- One compact chat line fragment: role + spec + numbers + run + note.
-- Callers prefix "Name: STATUS - ". No duplicated name, no extra lines.
local function MemberSummary(snap)
  local m = PrimaryMember(snap)
  if not m then return "?" end
  local roleTag = NS.RoleTag(NS.ResolveRole(m))
  local ilvl = (m.itemLevel and m.itemLevel > 0) and tostring(math.floor(m.itemLevel)) or "-"
  local score = FormatScore(m.dungeonScore, m.rioScore)
  local s = roleTag .. ", ilvl " .. ilvl .. ", M+ " .. score
  local li = snap and snap.listing
  if li and (li.dungeon or li.key) then
    s = s .. "  |cffffd100[" .. (li.key and ("+" .. li.key .. " ") or "") .. (li.dungeon or "?") .. "]|r"
  end
  local note = snap and snap.comment
  if note and note ~= "" then
    s = s .. '  |cff88bbff"' .. TruncNote(note, 60) .. '"|r'
  end
  return s
end


-- ---------------------------------------------------------------------------
-- Log (persisted) - UI lives in LogFrame.lua
-- ---------------------------------------------------------------------------

local function TrimLog()
  local maxN = (NS.db and NS.db.maxLogEntries) or 300
  local D = NS.Data()
  while #D.log > maxN do
    table.remove(D.log, 1)
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

local function CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Active DATA store (log + stats). All SETTINGS stay account-wide on NS.db.
-- Default is one shared log; perCharLog (opt-in) splits log+stats per char.
-- Switching preserves both sides: shared history stays in LFGAlertDB.log.
function NS.Data()
  NS.db = NS.db or LFGAlertDB
  if NS.db and NS.db.perCharLog then
    NS.db.chars = NS.db.chars or {}
    local k = CharKey()
    local c = NS.db.chars[k]
    if type(c) ~= "table" then
      c = { log = {}, stats = { sessions = {}, total = {
        queued = 0, invited = 0, accepted = 0, declined = 0, auto = 0, gone = 0 } } }
      NS.db.chars[k] = c
    end
    if type(c.log) ~= "table" then c.log = {} end
    return c
  end
  return NS.db or {}
end

local function DeepCopy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local c = {}
  seen[t] = c
  for k, v in pairs(t) do c[DeepCopy(k, seen)] = DeepCopy(v, seen) end
  return c
end

-- Toggle the per-character log. First enable seeds the fresh character store
-- from shared history, so flipping the switch never looks like data loss.
-- (Plain print, not the applicant NS.ChatMessage(): defined further down and
-- gated on alert settings - wrong tool for settings feedback anyway.)
function NS.SetPerCharLog(v)
  NS.db.perCharLog = v and true or false
  if v and LFGAlertDB and type(LFGAlertDB.log) == "table" and #LFGAlertDB.log > 0 then
    local D = NS.Data()
    if #(D.log or {}) == 0 then
      D.log = DeepCopy(LFGAlertDB.log)
      if type(LFGAlertDB.stats) == "table" then D.stats = DeepCopy(LFGAlertDB.stats) end
      print("|cffff2020[LFGAlert]|r Per-character log ON: seeded " .. #D.log .. " rows from shared history.")
    end
  end
  if NS.RefreshLogUI then NS.RefreshLogUI(true) end
end

local autoPending = {} -- applicantID -> true while OUR auto-decline is in flight

local function BucketFor(status)
  if status == "applied" then return "queued" end
  if status == "invited" then return "invited" end
  if status == "inviteaccepted" then return "accepted" end
  if status == "cancelled" or status == "timedout" then return "gone" end
  return "declined" -- declined, declined_full, declined_delisted, failed, invitedeclined
end

local function EnsureStats()
  local D = NS.Data()
  if type(D.stats) ~= "table" then
    D.stats = { sessions = {}, total = { queued = 0, invited = 0, accepted = 0, declined = 0, auto = 0, gone = 0 } }
  end
  if type(D.stats.sessions) ~= "table" then D.stats.sessions = {} end
  if type(D.stats.total) ~= "table" then
    D.stats.total = { queued = 0, invited = 0, accepted = 0, declined = 0, auto = 0, gone = 0 }
  end
  return D.stats
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
  for _, e in ipairs(NS.Data().log or {}) do
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
  local D = NS.Data()
  for i = #D.log, 1, -1 do
    local e = D.log[i]
    if e and not e.separator and e.applicantID == applicantID
      and (e.session == nil or e.session == listingSession) then
      entry = e
      break
    end
  end

  local now = time()
  if entry then
    if entry.session == nil then
      -- Adopted from before session tracking: drop stale listing context
      -- (dungeon/key/history from a previous listing) so everything below
      -- refills fresh. This is what once showed last week's key on new rows.
      entry.session = listingSession
      entry.t = now
      entry.dungeon, entry.dungeonFull, entry.key, entry.keySource, entry.listingTitle = nil, nil, nil, nil, nil
      entry.declineReason, entry.autoDeclined = nil, nil
      entry.history = {}
    end
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
    D.log[#D.log + 1] = entry
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
  NS.Data().log = {}
  if NS.RefreshLogUI then NS.RefreshLogUI() end
end


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
  NS.ChatMessage(l("auto_declined_fmt", "Auto-declined %s (%s)"):format(ShortName(m.name), table.concat(reasons, ", ")))
  return true
end

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

-- Already-terminal statuses: seeing these, a later disappearance needs no row.
local TERMINAL_STATUSES = {
  declined = true, declined_full = true, declined_delisted = true,
  cancelled = true, timedout = true, failed = true,
  inviteaccepted = true, invitedeclined = true,
}

local function IsApplicantPresent(applicantID)
  if not applicantID or not (C_LFGList and C_LFGList.GetApplicants) then return false end
  local ok, ids = pcall(C_LFGList.GetApplicants)
  if not ok or type(ids) ~= "table" then return false end
  for _, id in ipairs(ids) do if id == applicantID then return true end end
  return false
end

-- Session continuity across reloads: the runtime counter restarts at 1 while
-- persisted log rows keep the old number, which made the login scan treat
-- every existing applicant as brand-new (re-alert storm + duplicate rows +
-- ID actions refused). When a listing is (still) active, ADOPT the persisted
-- session number of the entries after the last separator instead of blindly
-- incrementing; a genuine new listing still increments.
local function AdoptOrIncrementSession()
  local log = (NS.Data() and NS.Data().log) or {}
  local lastSep = 0
  for i, e in ipairs(log) do
    if e.separator then lastSep = i end
  end
  local maxS = 0
  for i = lastSep + 1, #log do
    local e = log[i]
    if e and not e.separator and type(e.session) == "number" and e.session > maxS then
      maxS = e.session
    end
  end
  if maxS > 0 then
    listingSession = maxS
  else
    listingSession = listingSession + 1
  end
end

-- Pre-seed known[] from the log so applicants that queued BEFORE a reload are
-- never re-alerted as new (no sound, no toast, no popup on login).
local function PrimeKnownFromLog()
  for _, e in ipairs((NS.Data() and NS.Data().log) or {}) do
    if not e.separator and e.applicantID and e.applicantID ~= 0
      and e.session == listingSession and not TERMINAL_STATUSES[e.status]
      and known[e.applicantID] == nil then
      known[e.applicantID] = { status = e.status, snap = nil }
    end
  end
end

-- The applicant is gone from Blizzard's list (or their info call fails):
-- they cancelled, joined, or expired. Synthesize the terminal transition so
-- the log always shows an ending — but ONLY from non-terminal states, so a
-- decline/cancel that was already logged is never duplicated.
local function HandleApplicantGone(applicantID)
  local prev = known[applicantID]
  local old, snap = prev and prev.status, prev and prev.snap
  if (not old or TERMINAL_STATUSES[old]) and not prev then
    -- `known` is wiped on every reload: fall back to the persisted row so
    -- cancellations of previously-logged applicants still show an ending.
    local D = NS.Data()
    if type(D.log) == "table" then
      for i = #D.log, 1, -1 do
        local e = D.log[i]
        if e and not e.separator and e.applicantID == applicantID
          and (e.session == nil or e.session == listingSession)
          and e.status and not TERMINAL_STATUSES[e.status] then
          old = e.status
          snap = { members = e.members, numMembers = e.numMembers, comment = e.comment,
            listing = { dungeon = e.dungeon, dungeonFull = e.dungeonFull, key = e.key,
              source = e.keySource, title = e.listingTitle } }
          break
        end
      end
    end
  end
  if not old or TERMINAL_STATUSES[old] then return end
  local newStatus = (old == "invited") and "inviteaccepted" or "cancelled"
  known[applicantID] = { status = newStatus, snap = snap, gone = true }
  NS.AddLogEntry(applicantID, old, newStatus, snap, false)
  NS.AnnounceStatusChange(applicantID, old, newStatus, snap)
end

-- Single funnel for "we just fetched a fresh snapshot of an applicant":
-- both the full-list scan and the per-applicant event path call this, so
-- new-applicant alerts, status-change logging and data backfill behave
-- identically everywhere.
-- Member data often lags the applicant event by a second or two, which made
-- the toast style inconsistent (whoever's data was late got the generic
-- banner). Wait briefly (bounded ~2.4s) so the alert can be the rich one;
-- if data never comes, fall back to the generic banner + backfill promotion.
local DelayedApplicantAlert
DelayedApplicantAlert = function(applicantID, attempt)
  C_Timer.After(0.6, function()
    if not HasActiveListing() then return end
    local kp = known[applicantID]
    if kp then kp.alertPending = nil end
    -- Abort only on a POSITIVE non-applied status. Fresh applicants often
    -- return an info object with a NIL status ("not reported yet") - that is
    -- "unknown", NOT "left", and must never drop the alert (this exact
    -- assumption silently ate follow-up applicants' alerts in build 32-33).
    local ok, info = pcall(C_LFGList.GetApplicantInfo, applicantID)
    if ok and type(info) == "table" and info.applicationStatus ~= nil
      and info.applicationStatus ~= "applied" then
      Trace(string.format("#%s delayed: left queue (%s), abort",
        tostring(applicantID), tostring(info.applicationStatus)))
      return
    end
    local snap = SnapshotApplicant(applicantID)
    local prev = known[applicantID]
    if snap and prev then prev.snap = snap end
    if snap and SnapHasData(snap) then
      -- Data landed: side effects here, then the backfill fills the "?" row,
      -- prints the chat line and fires the rich toast (gated per role).
      Trace(string.format("#%s delayed: data landed on attempt %d", tostring(applicantID), attempt))
      local pm = snap.members[1]
      if not (NS.db and NS.db.muteAll) and RoleAlertAllowed("sound", pm) then
        NS.PlayAlertSound(tostring(applicantID), NS.ResolveRole(pm))
      end
      if NS.db and NS.db.autoOpenLFG and not (NS.db and NS.db.muteAll)
        and RoleAlertAllowed("popup", pm) then
        NS.OpenApplicants()
      end
      BackfillLogEntry(applicantID, snap)
    elseif attempt >= 4 then
      -- Still nothing: alert with what we know (generic banner); the normal
      -- scan/backfill retries will promote it to the rich toast later.
      Trace(string.format("#%s delayed: no data after %d attempts, generic alert", tostring(applicantID), attempt))
      local best = (snap and SnapHasData(snap) and snap) or (prev and prev.snap)
      if best then NS.AlertNewApplicant(applicantID, best) end
    else
      Trace(string.format("#%s delayed: attempt %d, still no data", tostring(applicantID), attempt))
      DelayedApplicantAlert(applicantID, attempt + 1)
    end
  end)
end


local function HandleApplicantSnapshot(applicantID, snap, reason)
  if not snap then return end
  local prev = known[applicantID]
  -- prev.status == nil means "seen but status not reported yet": treat like a
  -- first sighting so the eventual real "applied" status still alerts as NEW
  -- (otherwise it registered as a status CHANGE, which never alerts).
  if not prev or prev.status == nil then
    known[applicantID] = { status = snap.status, snap = snap }
    NS.AddLogEntry(applicantID, prev and prev.status, snap.status or "applied", snap, not prev)
    Trace(string.format("#%s new: status=%s data=%s", tostring(applicantID),
      tostring(snap.status), tostring(SnapHasData(snap))))
    if snap.status == "applied" then
      if SnapHasData(snap) then
        NS.AlertNewApplicant(applicantID, snap)
      elseif not known[applicantID].alertPending then
        -- One delayed chain per applicant, even if several events race.
        known[applicantID].alertPending = true
        DelayedApplicantAlert(applicantID, 1)
      end
      NS.MaybeAutoDecline(applicantID, snap)
    elseif snap.status ~= nil then
      NS.AnnounceStatusChange(applicantID, nil, snap.status, snap)
    end
  elseif prev.status ~= snap.status then
    local old = prev.status
    known[applicantID] = { status = snap.status, snap = snap }
    NS.AddLogEntry(applicantID, old, snap.status, snap, false)
    NS.AnnounceStatusChange(applicantID, old, snap.status, snap)
    -- Re-alert if they re-applied after cancel/decline (role-gated like
    -- first sighting; tagged so a double event still plays once).
    if snap.status == "applied" and reason == "list"
      and RoleAlertAllowed("sound", PrimaryMember(snap)) then
      NS.PlayAlertSound(tostring(applicantID), NS.ResolveRole(PrimaryMember(snap)))
    end
  else
    -- Same status: refresh snapshot (ilvl/score may have resolved late)
    -- and fill any "?" log rows now that data is available.
    prev.snap = snap
    NS.BackfillLogEntry(applicantID, snap)
  end
end

local function ScanApplicants(reason, retryN)
  if not NS.db or not NS.db.enabled then return end
  if not HasActiveListing() then return end
  -- Only the leader's client should scream. (Listing exists => we listed it.)
  if not IsGroupLeader() then return end
  if not C_LFGList.GetApplicants then return end

  -- A listing can be active before its event reaches us (login timing):
  -- settle the session first, then prime known[] so the login scan does not
  -- re-alert everyone who queued before the reload.
  if not NS._hadListing then
    AdoptOrIncrementSession()
    NS._hadListing = true
  end
  if reason == "login" then PrimeKnownFromLog() end

  local ok, ids = pcall(C_LFGList.GetApplicants)
  if not ok or type(ids) ~= "table" then
    Trace(string.format("scan(%s): GetApplicants failed (ok=%s)", reason or "?", tostring(ok)))
    return
  end
  Trace(string.format("scan(%s): %d applicant(s) listed", reason or "?", #ids))

  -- The listing is the same for every applicant in this scan: resolve it once
  -- (activity-info + keystone lookups) instead of once per applicant.
  local listing = NS.CurrentListingInfo()
  local rioMemo = {}

  local missingData = false
  local seen = {} -- applicant IDs present in this scan (used by the reconcile below)
  for _, applicantID in ipairs(ids) do
    seen[applicantID] = true
    local snap = SnapshotApplicant(applicantID, listing, rioMemo)
    if snap then
      if not SnapHasData(snap) then missingData = true end
      HandleApplicantSnapshot(applicantID, snap, reason)
    end
  end

  -- Reconcile: known IDs missing from the live list left the queue
  -- (cancelled, joined, expired). Log the ending exactly once — only from
  -- non-terminal states, so declines/cancels never double-log.
  for id in pairs(known) do
    if not seen[id] then HandleApplicantGone(id) end
  end

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
    if s and (s.queued or 0) > 0 and NS.db.statsSummary ~= false then
      NS.ChatMessage(StatLine(l("listing_over", "Listing over"), s))
    end
  end
  wipe(known)
  wipe(autoPending)
  if NS._autoReason then wipe(NS._autoReason) end
  local D = NS.Data()
  if reasonLabel and type(D.log) == "table" then
    -- Visual separator in the log so sessions don't blur together.
    D.log[#D.log + 1] = { t = time(), separator = l("sep_ended", "— listing ended —") }
    TrimLog()
    if NS.RefreshLogUI then NS.RefreshLogUI() end
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


-- Namespace exports used by Core's event handler and the Alerts file.
NS.SnapshotApplicant = SnapshotApplicant
NS.PrimaryMember = PrimaryMember
NS.SnapHasData = SnapHasData
NS.MemberSummary = MemberSummary
NS.HandleApplicantGone = HandleApplicantGone
NS.IsApplicantPresent = IsApplicantPresent
NS.ScanApplicants = ScanApplicants
NS._known = known
NS.HandleApplicantSnapshot = HandleApplicantSnapshot
NS.AdoptOrIncrementSession = AdoptOrIncrementSession
NS.CopySnapMembers = CopySnapMembers
