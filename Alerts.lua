-- LFGAlert - Alerts.lua (split from Core.lua)
LFGAlert = LFGAlert or {}
local NS = LFGAlert
local L = NS.L or {}
local function l(key, fallback) return L[key] or fallback end
local Trace = NS.Trace

local PrimaryMember = NS.PrimaryMember
local SnapHasData = NS.SnapHasData
local MemberSummary = NS.MemberSummary
local ShortName = NS.ShortName or function(n) return n or "?" end
local ClassColorize = NS.ClassColorize or function(_, text) return text end
local RoleAlertAllowed = NS.RoleAlertAllowed
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


-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------

local lastSoundKey, lastSoundAt = nil, 0

-- Curated sound presets for the role dropdowns (Options + /lfgalert).
-- Data-only: send more { id, label } pairs and they appear everywhere.
NS.SOUND_PRESETS = {
  -- { id, label, category } - single source for the role dropdowns. The three
  -- flagged (cat "featured") also headline the menu above the categories.
  { 556000, "Murloc Aggro", "featured" },
  { 547630, "Dragon Whelp Stand", "featured" },
  { 6053336, "Arathi Female Aggro", "featured" },
  { 8959, "Raid Warning", "featured" },
  { 8960, "Ready Check", "featured" },
  { 12867, "Level Up", "featured" },
  -- Aggro voices
  { 5985390, "Nerubian Female Aggro", "Aggro voices" },
  { 550523, "Goblin Pre-Aggro", "Aggro voices" },
  { 3586097, "Grunt Throg (VO)", "Aggro voices" },
  -- Ducks
  { 4618219, "Duck Quack Aggressive 1", "Ducks" },
  { 4618221, "Duck Quack 2", "Ducks" },
  { 4618223, "Duck Quack 3", "Ducks" },
  { 4618225, "Duck Quack 4", "Ducks" },
  { 4618227, "Duck Quack 5", "Ducks" },
  { 4618229, "Duck Quack 6", "Ducks" },
  { 4618231, "Duck Quack 7", "Ducks" },
  { 4618233, "Duck Quack 8", "Ducks" },
  { 4618235, "Duck Quack 9", "Ducks" },
  { 4618237, "Duck Quack 10", "Ducks" },
  { 4618239, "Duck Quack 11", "Ducks" },
  { 4618293, "Duck Quack Wound 1", "Ducks" },
  { 4618295, "Duck Quack Wound 2", "Ducks" },
  { 4618297, "Duck Quack Wound 3", "Ducks" },
  { 4618299, "Duck Quack Wound 4", "Ducks" },
  { 4618301, "Duck Quack Wound 5", "Ducks" },
  { 4618303, "Duck Quack Wound 6", "Ducks" },
  { 4618418, "Duckling Quack", "Ducks" },
  -- Goblins
  { 6350903, "Goblin Sapper 1", "Goblins" },
  { 6350905, "Goblin Sapper 2", "Goblins" },
  { 6350907, "Goblin Sapper 3", "Goblins" },
  { 549921, "Gilgoblin Attack 1", "Goblins" },
  { 549922, "Gilgoblin Attack 2", "Goblins" },
  { 6234967, "Oil Goblin Cast 1", "Goblins" },
  { 6234969, "Oil Goblin Cast 2", "Goblins" },
  { 6234971, "Oil Goblin Cast 3", "Goblins" },
  { 6234973, "Oil Goblin Cast 4", "Goblins" },
  { 6234975, "Oil Goblin Cast 5", "Goblins" },
  { 6234977, "Oil Goblin Cast 6", "Goblins" },
  { 6234979, "Oil Goblin Cast 7", "Goblins" },
  { 6234981, "Oil Goblin Cast 8", "Goblins" },
  { 6234983, "Oil Goblin Cast 9", "Goblins" },
  { 6234985, "Oil Goblin Cast 10", "Goblins" },
  { 6234987, "Oil Goblin Cast 11", "Goblins" },
  { 6234989, "Oil Goblin Cast 12", "Goblins" },
  { 6234991, "Oil Goblin Cast 13", "Goblins" },
  { 6234993, "Oil Goblin Cast 14", "Goblins" },
  { 6234995, "Oil Goblin Cast 15", "Goblins" },
  -- Monsters
  { 606671, "Saurok Crit", "Monsters" },
  { 1250663, "Banshee Death", "Monsters" },
  { 1036737, "Arakkoa Attack Crit", "Monsters" },
  { 1266209, "Eagle Wound", "Monsters" },
  { 1255468, "Imp Crit", "Monsters" },
  { 640068, "Mantid Tank Crit", "Monsters" },
  -- Weapons & FX
  { 569265, "Cannon 1", "Weapons & FX" },
  { 568561, "Cannon 2", "Weapons & FX" },
  { 774378, "Gibs Explode", "Weapons & FX" },
  -- Legacy cheers (kept labeled so existing saved picks resolve)
  { 543326, "Troll Cheer 3", "Cheers" },
  { 539228, "Troll Cheer 1", "Cheers" },
  { 4738557, "Dracthyr Cheer", "Cheers" },
  -- Misc
  { 567412, "Unlabeled 567412", "Misc" },
}

-- Play a sound by ID, auto-detecting its semantics: classic SoundKit IDs are
-- small and play via PlaySound; Wowhead-era IDs (roughly 100k+) are sound
-- FILE IDs which PlaySound silently ignores - those play via PlaySoundFile,
-- with a PlaySound fallback in case the number is a kit after all.
function NS.PlaySoundID(id, channel)
  id = tonumber(id)
  if not id or id <= 0 then return end
  if id >= 100000 then
    local ok, played = pcall(PlaySoundFile, id, channel)
    if ok and played ~= false then return end
  end
  pcall(PlaySound, id, channel)
end

function NS.PlayAlertSound(tag, role)
  if not NS.db or not NS.db.soundEnabled then return end
  -- Debounce: the same applicant pinging twice within 3s (double events,
  -- instant cancel+requeue spam) plays once. Distinct IDs always play.
  if tag then
    local now = GetTime()
    if tag == lastSoundKey and (now - lastSoundAt) < 3 then return end
    lastSoundKey, lastSoundAt = tag, now
  end
  local channel = NS.db.useMasterChannel and "Master" or nil
  -- Per-role sound: a role-specific custom FILE wins, then a role-specific
  -- SoundKit ID, then the global custom file / global ID - so each role is
  -- instantly recognizable by ear.
  if role then
    local roleKey = (role .. ""):upper()
    if roleKey == "DPS" then roleKey = "DAMAGER" end
    local file = NS.db.roleSoundFiles and NS.db.roleSoundFiles[roleKey]
    if type(file) == "string" and file ~= "" then
      local okF, playedF = pcall(PlaySoundFile, file, channel)
      if okF and playedF ~= false then
        Trace("sound: role " .. roleKey .. " file")
        return
      end
      -- Bad file path: fall through to the role's SoundKit ID.
    end
    local rid = NS.db.roleSounds and tonumber(NS.db.roleSounds[roleKey])
    if rid and rid > 0 then
      Trace("sound: role " .. roleKey .. " id " .. rid)
      NS.PlaySoundID(rid, channel)
      return
    end
  end
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
  NS.PlaySoundID(id, channel)
end


-- ---------------------------------------------------------------------------
-- Stacked center toasts. Blizzard's RaidWarningFrame holds only TWO messages
-- and silently drops/overwrites extras, so simultaneous applicants randomly
-- lost their on-screen alert (first/last/none). This own stack shows every
-- line: each toast holds ~4s, fades ~0.8s, up to 5 visible (oldest recycles).
-- ---------------------------------------------------------------------------
local toastFrame
local toastShown, toastPool = {}, {}
local TOAST_MAX, TOAST_HOLD, TOAST_FADE = 5, 4.0, 0.8

local function LayoutToasts()
  for i, ln in ipairs(toastShown) do
    ln:ClearAllPoints()
    if i == 1 then
      ln:SetPoint("TOP", toastFrame, "TOP", 0, 0)
    else
      ln:SetPoint("TOP", toastShown[i - 1], "BOTTOM", 0, -6)
    end
  end
end

local function UpdateToasts(_, elapsed)
  local removed = false
  for i = #toastShown, 1, -1 do
    local ln = toastShown[i]
    if ln.hold then
      ln.hold = ln.hold - elapsed
      if ln.hold <= 0 then
        ln.hold = nil
        ln.fade = TOAST_FADE
      end
    elseif ln.fade then
      ln.fade = ln.fade - elapsed
      if ln.fade <= 0 then
        ln:Hide()
        toastPool[#toastPool + 1] = ln
        table.remove(toastShown, i)
        removed = true
      else
        ln:SetAlpha(ln.fade / TOAST_FADE)
      end
    end
  end
  if removed then LayoutToasts() end
end

local function EnsureToastFrame()
  if toastFrame then return toastFrame end
  local ok, f = pcall(CreateFrame, "Frame", "LFGAlertToastFrame", UIParent)
  if not (ok and f) then return nil end
  toastFrame = f
  toastFrame:SetSize(640, 150)
  toastFrame:SetPoint("TOP", UIParent, "TOP", 0, -135)
  toastFrame:SetFrameStrata("HIGH")
  toastFrame:SetScript("OnUpdate", UpdateToasts)
  toastFrame:Show()
  return toastFrame
end

-- Applicant alerts come through here (NOT Blizzard's raid warning): same
-- on/off toggle, but every simultaneous applicant gets a visible line.
-- Hardened: any error inside the stack falls back to the Blizzard frame so
-- an alert can never be silently eaten by the toast system.
local function ApplicantToastShow(text)
  if not EnsureToastFrame() then return false end
  local line = table.remove(toastPool)
  if not line then
    line = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  end
  line:SetText(text)
  line:SetAlpha(1)
  line.hold, line.fade = TOAST_HOLD, nil
  line:Show()
  toastShown[#toastShown + 1] = line
  if #toastShown > TOAST_MAX then
    local old = table.remove(toastShown, 1)
    old:Hide()
    toastPool[#toastPool + 1] = old
  end
  LayoutToasts()
  return true
end

local function ApplicantToast(text)
  if not (NS.db and NS.db.raidWarning) then return end
  local ok, shown = pcall(ApplicantToastShow, text)
  if not ok or shown == false then
    Trace("toast: stack failed (" .. tostring(ok) .. "), falling back to raid warning")
    CenterMessage(text)
  end
end

local function ChatMessage(text)
  if not NS.db or not NS.db.chatMessage then return end
  print("|cffff2020[LFGAlert]|r " .. text)
end

-- Rich center toast: name + role (icon + colored Tank/Heal/DPS) + class-colored
-- spec. Used by the instant alert AND by the backfill path once member data
-- lands (upgrading the generic "New applicant!" banner).
local function CenterRichAlert(_, snap)
  local pm = snap and snap.members and snap.members[1]
  if not (pm and pm.name) then return end
  if NS.db and NS.db.muteAll then return end
  if not RoleAlertAllowed("screen", pm) then return end
  local roleTag = NS.RoleTag(NS.ResolveRole(pm))
  local specTxt = pm.specName or pm.localizedClass or pm.class or ""
  if pm.class then specTxt = ClassColorize(pm.class, specTxt) end
  ApplicantToast(l("alert_center_fmt", "New applicant: %s - %s %s"):format(ShortName(pm.name), roleTag, specTxt))
end

function NS.AlertNewApplicant(applicantID, snap)
  if NS.db and NS.db.muteAll then return end -- master mute: log still records
  local pm = PrimaryMember(snap)
  if NS.db and NS.db.traceAlerts then
    print(string.format("[LFGAlert] trace #%s role=%s sound=%s chat=%s screen=%s popup=%s",
      tostring(applicantID), tostring(NS.ResolveRole(pm)),
      tostring(RoleAlertAllowed("sound", pm)), tostring(RoleAlertAllowed("chat", pm)),
      tostring(RoleAlertAllowed("screen", pm)), tostring(RoleAlertAllowed("popup", pm))))
  end
  if RoleAlertAllowed("sound", pm) then NS.PlayAlertSound(tostring(applicantID), NS.ResolveRole(pm)) end
  if NS.db and NS.db.flashTaskbar and FlashClientIcon then
    pcall(FlashClientIcon)
  end
  if NS.db and NS.db.autoOpenLFG and RoleAlertAllowed("popup", pm) then
    Trace("popup: opening Group Finder applicants")
    NS.OpenApplicants()
  end
  if not SnapHasData(snap) then
    -- Details not ready yet: keep the sound + a generic banner now;
    -- BackfillLogEntry prints the compact line once data lands.
    if RoleAlertAllowed("screen", pm) then
      ApplicantToast(l("alert_banner", "New applicant!"))
    end
    return
  end
  local name = pm and pm.name or ("#" .. tostring(applicantID))
  if RoleAlertAllowed("screen", pm) then
    CenterRichAlert(applicantID, snap)
  end
  if RoleAlertAllowed("chat", pm) then
    local qLabel, qColor = NS.StatusLabel("applied")
    ChatMessage(ShortName(name) .. ": |cff" .. qColor .. qLabel .. "|r - " .. MemberSummary(snap))
  end
end

function NS.AnnounceStatusChange(applicantID, _, newStatus, snap)
  -- Flood control: chat only for fresh invites. Accepts, declines and leaves
  -- live in the log (and stats) only.
  if newStatus ~= "invited" then return end
  if NS.db and NS.db.muteAll then return end
  local pm = PrimaryMember(snap)
  if not RoleAlertAllowed("chat", pm) then return end
  local label, color = NS.StatusLabel(newStatus)
  local name = (pm and pm.name) or ("#" .. tostring(applicantID))
  ChatMessage(ShortName(name) .. ": |cff" .. color .. label .. "|r - " .. MemberSummary(snap))
end

-- Member data is often unavailable on the first event (Blizzard sends the
-- list before the details). This fills previously-logged "?" rows once the
-- data arrives, and prints the full detail line if it was skipped earlier.
local function BackfillLogEntry(applicantID, snap)
  if not SnapHasData(snap) then return false end
  local D = NS.Data()
  if type(D.log) ~= "table" then return false end
  local changed = false
  for _, e in ipairs(D.log) do
    if not e.separator and e.applicantID == applicantID
      and (e.session == nil or e.session == NS.CurrentListingSession()) then
      local em = e.members and e.members[1]
      if not (em and em.name) then
        e.members = e.members or {}
        NS.CopySnapMembers(e.members, snap)
        e.numMembers = snap.numMembers or e.numMembers
        if snap.comment and snap.comment ~= "" then e.comment = snap.comment end
        if e.dungeon == nil and snap.listing and snap.listing.dungeon then
          e.dungeon, e.dungeonFull, e.key, e.keySource, e.listingTitle =
            snap.listing.dungeon, snap.listing.dungeonFull, snap.listing.key, snap.listing.source, snap.listing.title
        end
        if not e.detailShown then
          e.detailShown = true
          local bSnap = { members = e.members, numMembers = e.numMembers, comment = e.comment, listing = snap.listing }
          local bMem = bSnap.members and bSnap.members[1]
          if RoleAlertAllowed("chat", bMem) and not (NS.db and NS.db.muteAll) then
            local bName = (bMem and bMem.name) or ("#" .. tostring(applicantID))
            local bLabel, bColor = NS.StatusLabel("applied")
            ChatMessage(ShortName(bName) .. ": |cff" .. bColor .. bLabel .. "|r - " .. MemberSummary(bSnap))
          end
          -- Promote the generic "New applicant!" banner to the rich toast
          -- now that the member data (role/spec) is finally known.
          CenterRichAlert(applicantID, bSnap)
        end
        -- MaybeAutoDecline re-verifies the applicant is still pending, so it
        -- is safe to attempt on every backfill.
        NS.MaybeAutoDecline(applicantID, snap)
        NS.MaybeAutoAccept(applicantID, snap)
        changed = true
      end
    end
  end
  if changed and NS.RefreshLogUI then NS.RefreshLogUI() end
  return changed
end
NS.BackfillLogEntry = BackfillLogEntry

-- Delayed alert continuation (called from HandleApplicantSnapshot above via
-- the local declared here; assignment must precede the handler's call site,
-- which is further down the file).


-- ---------------------------------------------------------------------------
-- Open Blizzard's Group Finder on your applicant list
-- Uses live FrameXML entry points (Blizzard_GroupFinder/Mainline/LFGList.lua):
--   PVEFrame_ShowFrame("GroupFinderFrame") + LFGListFrame_SetActivePanel(..., ApplicationViewer)
-- ---------------------------------------------------------------------------

NS._pendingOpenLFG = false

function NS.OpenApplicants()
  -- Never fight the UI during combat: queue the open for when combat drops
  -- (PLAYER_REGEN_ENABLED below picks it up).
  if InCombatLockdown and InCombatLockdown() then
    NS._pendingOpenLFG = true
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


NS.ChatMessage = ChatMessage
NS.ApplicantToast = ApplicantToast
