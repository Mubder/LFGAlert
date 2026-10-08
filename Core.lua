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
NS.BUILD = 47 -- bump every shipment; shown in load message + /lfgalert debug

-- Quiet trace channel (/lfgalert trace on): prints scan/detection decisions
-- so alert dropouts can be diagnosed from one chat dump.
local function Trace(msg)
  if NS.db and NS.db.traceAlerts then
    print("|cff888888[LFGAlert] trace|r " .. msg)
  end
end
NS.Trace = Trace -- shared with the split files

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
  -- Master + session-summary mutes (everything else has its own checkbox).
  muteAll = false,
  statsSummary = true,
  -- Log scope: shared account-wide by default; perCharLog splits per character.
  perCharLog = false,
  chars = {},
  -- Group log rows under their key ("+10 Altar of Fangs (3)").
  groupByKey = true,
  -- Per-role alert gates, one set per channel (all ON = current behavior).
  alertRoles = {
    sound = { TANK = true, HEALER = true, DAMAGER = true },
    chat = { TANK = true, HEALER = true, DAMAGER = true },
    screen = { TANK = true, HEALER = true, DAMAGER = true },
    popup = { TANK = true, HEALER = true, DAMAGER = true },
  },
  -- Per-role alert sounds (SoundKit IDs). nil/0 = use the global sound.
  -- Distinct voice lines so you can hear WHO signed up without looking:
  -- tank = troll male cheer #3, healer = troll male cheer #1,
  -- dps = dracthyr allied-race cheer.
  roleSounds = { TANK = 543326, HEALER = 539228, DAMAGER = 4738557 },
  -- Optional per-role custom sound FILES (override the role's SoundKit ID).
  roleSoundFiles = { TANK = "", HEALER = "", DAMAGER = "" },
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
NS.HasActiveListing = HasActiveListing
NS.IsGroupLeader = IsGroupLeader

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

-- Blizzard's INLINE_*_ICON globals changed shape across patches (classic
-- texture tags vs atlas markup), and broken markup renders as "???" in chat.
-- Trust the global when it is one of the two known-good chat-safe forms
-- (classic |T...|t or modern atlas |A:...|a); otherwise fall back to the
-- classic role-icon texture coordinates (stable since MoP).
local ROLE_ICON_FALLBACK = {
  TANK    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:0:19:22:41|t",
  HEALER  = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:1:20|t",
  DAMAGER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:22:41|t",
}

local function SafeRoleIcon(iconKey, roleKey)
  local s = iconKey and _G[iconKey]
  if type(s) == "string" and s ~= "" then
    if s:match("^|TInterface\\.+|t$") or s:match("^|A:.+|a$") then return s end
  end
  return ROLE_ICON_FALLBACK[roleKey] or ""
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
  local icon = SafeRoleIcon(iconKey, key)
  if icon ~= "" then icon = icon .. " " end
  return icon .. "|cff" .. color .. label .. "|r", label
end

-- Per-role alert gate for one channel ("sound" | "chat" | "screen").
-- Unknown role (no data yet) always passes; only a KNOWN unchecked role mutes.
-- Missing config also passes, preserving old behavior.
local function RoleAlertAllowed(channel, mem)
  local cfg = NS.db and NS.db.alertRoles and NS.db.alertRoles[channel]
  if cfg == nil then return true end
  local role = NS.ResolveRole(mem)
  if not role then return true end
  local v = cfg[role]
  if v == nil then return true end
  return v and true or false
end
NS.RoleAlertAllowed = RoleAlertAllowed -- shared (Applicants + Alerts)


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
    local loaded = l("msg_loaded", "LFGAlert loaded (build %s). /lfgalert for log & options.")
      :format(tostring(NS.BUILD))
    print("|cffffcc00" .. loaded .. "|r")
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    -- Open the applicant list that was deferred while in combat.
    if NS._pendingOpenLFG then
      NS._pendingOpenLFG = false
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
        local snap = NS.SnapshotApplicant(applicantID)
        if not snap then
          -- Info already gone: if they're also off the live list, they left
          -- (cancelled/joined) — log the ending instead of dropping it.
          -- If still listed, the data is just late: take one more full pass.
          if NS.IsApplicantPresent(applicantID) then
            NS.Rescan("retry")
          else
            NS.HandleApplicantGone(applicantID)
          end
          return
        end
        NS.HandleApplicantSnapshot(applicantID, snap, "updated")
        if not NS.SnapHasData(snap) then
          -- Details still not ready: retry a few times, then give up.
          local prev = NS._known[applicantID]
          if prev then
            local n = (prev.retries or 0) + 1
            prev.retries = n
            if n <= 4 then
              C_Timer.After(2, function()
                if not HasActiveListing() then return end
                local s2 = NS.SnapshotApplicant(applicantID)
                if s2 then
                  local p2 = NS._known[applicantID]
                  if p2 then p2.snap = s2 end
                  NS.BackfillLogEntry(applicantID, s2)
                elseif not NS.IsApplicantPresent(applicantID) then
                  NS.HandleApplicantGone(applicantID)
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
      if not NS._hadListing then
        NS.AdoptOrIncrementSession()
      end
      NS._hadListing = true
      NS.Rescan("entry")
    else
      NS._hadListing = false
      NS.WipeKnown("— listing ended —")
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(2, function() NS.ScanApplicants("login") end)
  end
end)


-- ---------------------------------------------------------------------------
-- Keybindings (Bindings.xml, bindable in Game Menu > Key Bindings > LFGAlert)
-- ---------------------------------------------------------------------------

BINDING_HEADER_LFGALERT = "LFGAlert"
BINDING_NAME_LFGALERT_TOGGLELOG = "Toggle applicant log"
BINDING_NAME_LFGALERT_OPENAPPLICANTS = "Open Group Finder applicants"

function LFGAlert.ToggleLogKeybind()
  if NS.ToggleLogUI then NS.ToggleLogUI() end
end

function LFGAlert.OpenApplicantsKeybind()
  NS.OpenApplicants()
end