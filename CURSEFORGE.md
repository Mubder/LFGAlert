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

LFGAlert — never miss an applicant again. When someone signs up to your Premade
Group listing you get a sound, a center-screen raid warning, and a full
applicant log: class, spec, role, item level, and Mythic+ score at a glance.

📝 Applicant log
Every applicant gets ONE row. The Status column is a lifecycle icon strip:
🔔 queued → ⏳ invited → ✅ accepted, plus ✕ for declined/left — stages that
happened are colored, the rest greyed out, and hovering the row shows the full
transition timeline with timestamps. Table columns: Time | Applicant |
Class/Spec | Role | Key | iLvl | M+ Score | Status | Notes. Class icons,
class-colored names, zebra striping, rows tinted by status (green accepted,
red declined, gold queued) and fresh applicants flash so you spot them
instantly. Hover any row for full details: group members, notes, both Blizzard
and Raider.IO scores.

🖱️ Smooth scrolling + sortable columns
The whole history is one scrollable list — mouse wheel or scrollbar, no paging.
Click any column header (Time, Applicant, Key, iLvl, M+ Score, Status) to sort
and find your best applicant in one click. The window is resizable and
remembers its position, size and scale between sessions.

🗝️ Dungeon + key level
Each row shows the run it queued for (e.g. +5 AOF), captured from your live
listing and stored per entry so it survives delists. Queue messages append the
run too.

🧙 Know who you're inviting
Class-colored names, spec, role, item level and Mythic+ score (Blizzard
rating, or Raider.IO automatically when installed). Group applications list
every member in the tooltip.

⚡ Fast, safe actions
One-click whisper / invite / decline buttons on every row, plus a right-click
menu. Left-click selects a row — no accidental whispers. And because applicant
IDs reset every time you relist, LFGAlert only sends invite/decline for rows
from your current listing: it can never act on the wrong person.

★ Requirements + auto-decline
Set a min item level / M+ score (sliders in settings): qualifying rows turn
green with a ★, and optional auto-decline removes undergeared applicants for
you (announced in chat, always logged, never fires without real data).

🔎 Filters + search
Status, Class and minimum-Key filters plus text search (name / spec / dungeon /
note), one-click "Reset Filters". Auto-declines show their reason
(Declined (Low ILvl)).

🔊 Your sound, your way
SoundKit presets, custom IDs, or your own .ogg/.mp3 file.

📊 Stats
Per-listing summary in chat on delist, plus all-time totals, accept rate and
accepted ilvl/M+ averages.

⚙️ Full settings UI
Esc → Options → AddOns → LFGAlert (or /lfgalert config): alerts, sound presets
+ custom file, window scale + reset, threshold sliders, auto-decline, stats.

Slash commands: /lfgalert show, hide, toggle, clear, test, sound, soundfile,
filter, minilvl, minscore, autodecline, stats, window, open, resetui, config,
on, off (/lfga shorthand)

Notes & FAQ

• Alerts fire only while you have an active listing (leader).
• Midnight hides listing/applicant text from addons: LFGAlert strips those
  unreadable tokens and can use your own keystone for dungeon/key while
  pushing your key (toggleable in settings).
• Auto-opening the Group Finder waits until you leave combat.
• No dependencies. Optional: Raider.IO for RIO scores.
• History and settings persist per account (up to 300 log rows, last 30
  listing sessions of stats).
• Translation-ready (Locales/enUS.lua). MIT licensed.

## First-release changelog (v1.0.14)

- Sound + raid-warning + chat alert on new applications, leader-only
- Auto-opens Group Finder on the applicant list
- Blizzard-styled log: status/class/key filters, one-click row actions,
  status tints, decline reasons, hover tooltips
- Threshold highlights, optional auto-decline, session + all-time stats
- Custom sounds, minimap button, full settings UI

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
