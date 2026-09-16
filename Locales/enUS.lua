-- LFGAlert - Locales/enUS.lua
-- Default (English) strings. Load order (see LFGAlert.toc) puts this file
-- first so Core.lua / LogFrame.lua / Options.lua can pick up NS.L.
-- Translations: copy this file to e.g. Locales/deDE.lua and translate the
-- values (not the keys), then list it in the .toc for that locale.
-- Slash-command output and /lfgalert debug stay inline English by design.
local ADDON_NAME = ...
LFGAlert = LFGAlert or {}
local L = {}
LFGAlert.L = L

-- Log window -----------------------------------------------------------------
L.log_title         = "LFGAlert Applicant Log"
L.footer_hint       = "Left-click: select  •  Right-click: whisper / invite / decline  •  Scroll: browse  •  Click a column header to sort"
L.entries_fmt       = "%d of %d entries"
L.empty_none        = "No applicants logged yet — new queues will appear here"
L.empty_filtered    = "No match — set Filter: All and clear the search box"
L.search_hint       = "Search..."
L.btn_clear_log     = "Clear Log"
L.btn_test_sound    = "Test sound"
L.btn_reset_filters = "Reset Filters"

L.col_time   = "Time"
L.col_name   = "Applicant"
L.col_role   = "Role"
L.col_spec   = "Class/Spec"
L.col_run    = "Key"
L.col_ilvl   = "iLvl"
L.col_score  = "M+ Score"
L.col_status = "Status"
L.col_note   = "Notes"

L.f_status = "Status:"
L.f_class  = "Class:"
L.f_key    = "Key:"
L.fmt_status_btn = "Status: %s"
L.fmt_class_btn  = "Class: %s"
L.fmt_key_btn    = "Key: %s"

-- Status labels (colors live in Core.lua STATUS_META)
L.st_applied           = "QUEUED"
L.st_invited           = "INVITED"
L.st_inviteaccepted    = "ACCEPTED"
L.st_declined          = "DECLINED"
L.st_declined_full     = "DECLINED (FULL)"
L.st_declined_delisted = "DECLINED (DELISTED)"
L.st_cancelled         = "CANCELLED"
L.st_timedout          = "TIMEOUT"
L.st_failed            = "FAILED"
L.st_invitedeclined    = "DECLINED INVITE"

-- Roles
L.role_tank   = "Tank"
L.role_healer = "Heal"
L.role_dps    = "DPS"

-- Filters
L.filter_all      = "All"
L.filter_queued   = "Queued"
L.filter_invited  = "Invited"
L.filter_accepted = "Accepted"
L.filter_declined = "Declined"
L.filter_gone     = "Cancelled / Timeout"
L.status_filter_title = "Filter by status"
L.class_filter_title  = "Filter by class"
L.key_filter_title    = "Minimum key level"
L.all_classes = "All Classes"
L.all_keys    = "All Keys"
L.min_key_fmt = "Minimum +%d"
L.key_label_fmt = "+%d+"

-- Row actions / context menu
L.act_whisper = "Whisper"
L.act_invite  = "Invite to group"
L.act_decline = "Decline applicant"
L.m_whisper     = "Whisper"
L.m_invite_name = "Invite to group (by name)"
L.m_accept      = "Accept applicant (LFG invite)"
L.m_decline     = "Decline applicant"
L.m_copy_name   = "Copy name"

-- Tooltips
L.tt_role        = "Role"
L.tt_run         = "Run"
L.tt_listing     = "Listing"
L.tt_ilvl        = "Item level"
L.tt_blizz       = "M+ rating (Blizzard)"
L.tt_rio         = "RIO score"
L.tt_rio_install = " (install Raider.IO)"
L.tt_group_fmt   = "Group application (%d):"
L.tt_status_fmt  = "Status: %s"
L.tt_rc_hint     = "Right-click: whisper / invite / decline"
L.tt_yourkey     = " (your key)"

-- Log row text
L.declined_label = "Declined"
L.auto_label     = "Auto"
L.queued_star    = "Queued ★"

-- Alerts / chat ---------------------------------------------------------------
L.msg_loaded        = "LFGAlert loaded (build %s). /lfgalert for log & options."
L.alert_banner      = "New applicant!"
L.alert_center_fmt  = "New applicant: %s (%s)"
L.alert_chat_fmt    = "New applicant: %s"
L.note_fmt          = 'Note: "%s"'
L.auto_declined_fmt = "Auto-declined %s (%s)"
L.ar_both  = "Low ILvl/M+"
L.ar_ilvl  = "Low ILvl"
L.ar_score = "Low M+"
L.sep_ended = "— listing ended —"

-- Stats
L.stats_header      = "LFGAlert stats:"
L.this_listing      = "This listing"
L.this_listing_none = "This listing: no queues yet"
L.all_time          = "All time"
L.listing_over      = "Listing over"
L.stats_line_fmt    = "%s: %d queued • %d accepted (%d%%) • %d declined%s • %d invited • %d left"
L.stats_auto_paren  = " (%d auto)"
L.stats_avg_fmt     = "  Accepted avg (n=%d): ilvl %d%s"
L.stats_avg_score   = " M+ %d"

-- Options panel ---------------------------------------------------------------
L.opt_title = "LFGAlert - Group Finder applicant alerts"
L.opt_version_fmt = "Version %s  •  build %s  •  /lfgalert for commands"
L.sec_general = "General"
L.sec_alerts  = "Alerts & Sound"
L.sec_window  = "Log Window"
L.sec_req     = "Requirements (highlight ★ + auto-decline)"
L.sec_data    = "Data & Stats"
L.sec_about   = "About"

L.cb_enable      = "Enable LFGAlert"
L.cb_minimap     = "Show minimap button (left: log, right: sound, drag: move)"
L.cb_autoopen    = "Open Group Finder applicants on new queue"
L.cb_ownkey      = "Use my own keystone for dungeon/key when listing text is hidden"
L.cb_sound       = "Play sound on new application"
L.cb_rw          = "Show raid-warning in screen center"
L.cb_chat        = "Show chat message"
L.cb_flash       = "Flash taskbar on new application"
L.cb_custom      = "Use custom sound file instead of Sound ID"
L.cb_autodecline = "Auto-decline below thresholds (only with real data)"

L.lbl_sound_id  = "Sound ID:"
L.lbl_file_path = "File path:"
L.note_presets  = "Presets (click to preview):"
L.preset_rw     = "Raid Warning"
L.preset_ready  = "Ready Check"
L.preset_level  = "Level Up"
L.btn_test      = "Test sound"
L.note_custom_example = "Example: Interface\\AddOns\\LFGAlert\\Sounds\\alert.ogg  (drop your own .ogg/.mp3 into the addon folder; restart WoW so it sees new files)"
L.note_req = "Rows at/above these get a ★ and green numbers, and auto-decline judges by them. 0 = off. Exact values via /lfgalert minilvl <n> and /lfgalert minscore <n>."
L.slider_ilvl  = "Min item level"
L.slider_score = "Min M+ score"
L.slider_scale = "Log window scale"
L.btn_show_stats  = "Show stats"
L.btn_reset_stats = "Reset stats"
L.btn_clear_log   = "Clear log"
L.btn_open_log    = "Open applicant log"
L.btn_reset_ui    = "Reset window position & size"
L.stats_summary_fmt = "All time: %d queued • %d accepted • %d declined%s"
L.no_stats    = "No stats yet."
L.note_stats  = "Stats keep the last 30 listings plus all-time totals. Per-listing summary prints to chat on delist."
L.note_about  = "Log window: scroll to browse history, click column headers to sort, left-click selects a row, right-click for whisper / invite / decline. Full command list: /lfgalert (no args)."

-- Minimap button
L.mm_open  = "Left-click: open applicant log"
L.mm_sound = "Right-click: sound on/off (now: %s)"
L.mm_drag  = "Drag: move minimap icon"
L.on  = "ON"
L.off = "OFF"
