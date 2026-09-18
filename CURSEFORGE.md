# CurseForge project info for LFGAlert

Copy-paste kit for creating the project page at
https://authors.curseforge.com/#/projects/create/choose-game (game: World of Warcraft).

## Project fields

- **Name:** LFGAlert
- **Game:** World of Warcraft (Retail)
- **Categories:** Miscellaneous (primary), Guild
- **License:** MIT (see `LICENSE` in this repo)
- **Short summary** (shown in search results — keep under ~250 chars):

> Sound alert + applicant log for your Premade Group listings: who queued, class/spec/ilvl/M+ score, key level, right-click whisper/invite, auto-decline and stats.

## Full description (paste into the project description editor)

LFGAlert — never miss an applicant. The moment someone signs up to your Premade Group you get a sound, a center-screen warning, a taskbar flash and a smart log that tells you who's worth inviting.

📝 One row per applicant with a lifecycle icon strip: queued → invited → accepted, plus ✕ for declined/left — stages that happened are colored, the rest greyed out, and cancellations show the moment someone withdraws. Hover for the full timeline, group members and both Blizzard + Raider.IO scores.

🔎 Find your best applicant fast — one scrollable, sortable list (click any column header), a resizable window that remembers its position, size and scale, Status/Class/Key filters, text search and one-click reset.

🧙 Know who you're inviting — class-colored names, spec, role, item level and Mythic+ score (Blizzard rating, or Raider.IO automatically when installed). Group applications list every member in the tooltip.

⚡ Fast, safe actions — one-click whisper / invite / decline buttons plus a right-click menu. Invite and decline only ever act on your current listing, so an old row can never hit the wrong person.

★ Requirements + auto-decline — set a min item level / M+ score: qualifying rows turn green with a star, and optional auto-decline removes the rest for you (always announced, always logged, never fires without real data).

🔔 Four alerts, your call — sound (Master channel, so you hear it even with game audio low), center-screen raid warning, chat message and taskbar flash. Each one toggles independently.

📊 Stats per listing and all-time (accept rate, accepted ilvl/M+ averages), custom sounds (.ogg/.mp3 or any SoundKit ID), a minimap button (left: open log, right: sound on/off, drag to move) and a full settings UI — Esc → Options → AddOns → LFGAlert.

Slash: /lfgalert show, test, sound, minilvl, minscore, autodecline, stats, config and more (/lfga shorthand).

Leader-only alerts • no dependencies (Raider.IO optional) • Midnight-ready • MIT licensed

## First-release changelog (v1.0.14)

- Sound + raid-warning + chat alert on new applications, leader-only
- Auto-opens Group Finder on the applicant list
- Blizzard-styled log: status/class/key filters, one-click row actions,
  status tints, decline reasons, hover tooltips
- Threshold highlights, optional auto-decline, session + all-time stats
- Custom sounds, minimap button, full settings UI

## Changelog v1.0.20

- Fixed "queued then cancelled, but the log never showed it": the
  vanish-detection loop crashed on every scan (missing lookup table), so
  cancellations were never logged. Queue → cancel now marks the row
  CANCELLED (grey X icon, chat line, tooltip timeline)

## Changelog v1.0.18

- Log window reverted to the classic translucent dark-navy backdrop with the
  gold dialog border (no Blizzard frame template — renders identically on
  every client); layout re-spaced for the thicker border

## Changelog v1.0.17

- Fixed a login bug on some clients: the log window could appear half-built
  and the minimap button/settings panel failed to load (a Blizzard scroll
  template was missing). Scrolling is now fully self-contained, the window
  hides immediately on creation, and each UI part builds independently with
  visible error reporting in chat

## Changelog v1.0.16

- **One row per applicant**: status transitions update the row instead of
  stacking "Queued / Invited / Accepted" duplicates
- **Lifecycle icon strip** in the Status column: queued → invited → accepted,
  ✕ declined/left. Reached stages colored, unreached greyed; hover for the
  full timeline with timestamps
- UI polish: gold-framed list area, dark header band, zebra striping, gold
  selection accent, gold title accents

## Changelog v1.0.15

- **Log window rebuilt**: smooth scrolling through full history (paging gone),
  sortable columns (click headers), resizable window that remembers position /
  size / scale, class icons, new-applicant row flash, left-click selects
  (whisper stays a deliberate action), one-click Reset Filters, Esc closes
- **Safety fix**: applicant IDs reset on relist, so invite/decline-by-ID now
  only act on rows from the current listing — stale rows use safe by-name
  invites and can never decline the wrong person
- Auto-open Group Finder now waits for combat to end instead of erroring
- Custom sound files now fall back to the SoundKit ID when the file is invalid
- Performance: listing info + Raider.IO scores resolved once per scan instead
  of per applicant; log UI refreshes coalesce bursts
- Localized UI strings via `Locales/enUS.lua` (translation-ready), MIT
  `LICENSE`, luacheck + CI

## Upload checklist

1. Zip layout must be `LFGAlert/LFGAlert.toc` (+ `Core.lua`, `LogFrame.lua`,
   `Options.lua`, `Locales/`) at the top level — exactly this folder.
2. Game version: Retail 12.x. Release type: Release.
3. Attach 2–3 screenshots: (a) log window with rows next to the Group Finder
   applicants tab, (b) settings panel, (c) chat alert lines.
4. Tag the release in git: `git tag v1.0.15` + `git push --tags` (matches
   `.pkgmeta` for auto-packaging).
