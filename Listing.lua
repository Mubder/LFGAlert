-- LFGAlert - Listing.lua (split from Core.lua)
LFGAlert = LFGAlert or {}
local NS = LFGAlert

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

