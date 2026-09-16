-- luacheck config for LFGAlert (WoW addon, Lua 5.1)
-- Run: luacheck .   (CI runs this on every push/PR)
std = "max"
cache = true
max_line_length = 120

-- Globals this addon creates.
globals = {
  "LFGAlert",
  "LFGAlertDB",
  "SlashCmdList",
  "SLASH_LFGALERT1",
  "SLASH_LFGALERT2",
  -- Named frames created at runtime (UISpecialFrames / template children)
  "LFGAlertLogFrame",
  "LFGAlertLogScroll",
  "LFGAlertLogScrollBar",
  "LFGAlertDropMenu",
  "LFGAlertClassMenu",
  "LFGAlertKeyMenu",
  "LFGAlertFilterMenu",
  "LFGAlertMinimapButton",
}

-- WoW API + FrameXML we read. Not exhaustive: extend as new APIs are used.
read_globals = {
  -- Lua-adjacent WoW helpers
  "wipe", "strsplit", "strtrim", "date", "time", "tinsert",
  -- Frames / widgets
  "CreateFrame", "UIParent", "Minimap", "GameTooltip", "UISpecialFrames",
  "RAID_CLASS_COLORS", "LOCALIZED_CLASS_NAMES_MALE",
  "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "GameFontHighlightSmall",
  "SELECTED_CHAT_FRAME", "DEFAULT_CHAT_FRAME",
  -- C_* namespaces
  "C_Timer", "C_LFGList", "C_MythicPlus", "C_ChallengeMode", "C_PartyInfo",
  "C_AddOns", "C_Texture",
  -- API functions
  "PlaySound", "PlaySoundFile", "FlashClientIcon",
  "RaidNotice_AddMessage", "RaidWarningFrame", "UIErrorsFrame", "ChatTypeInfo",
  "GetSpecializationInfoByID", "GetRealmName", "GetCursorPosition",
  "UnitIsGroupLeader", "UnitName", "UnitClass", "UnitLevel", "IsInGroup",
  "InCombatLockdown", "GetMouseFoci",
  -- Menus / chat interop
  "MenuUtil", "EasyMenu", "UIDropDownMenuTemplate",
  "ChatFrame_OpenChat", "ChatEdit_ChooseBoxForSend",
  -- Settings (modern + legacy)
  "Settings", "InterfaceOptionsFrame_OpenToCategory", "InterfaceOptions_AddCategory",
  -- Scroll frame helpers (FauxScrollFrameTemplate)
  "FauxScrollFrame_OnVerticalScroll", "FauxScrollFrame_Update", "FauxScrollFrame_GetOffset",
  -- Misc template callbacks
  "InCombatLockdown",
  -- Optional addon
  "RaiderIO",
}

-- Unused self/placeholder args are common in WoW script handlers.
ignore = {
  "212/self", "212/_", "212/button", "212/delta", "212/value",
  "213",   -- unused loop variable
  "542",   -- empty if branch (defensive guards)
}
