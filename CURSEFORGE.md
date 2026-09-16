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

**LFGAlert** makes leading Premade Groups effortless. When someone applies to
your Group Finder listing you get a sound, a center-screen warning, and your
Group Finder jumps straight to the applicant list.

📝 **Applicant log** — every signup is recorded: queued, invited, accepted,
declined, cancelled or timed out. Blizzard-styled table: Time | Applicant |
Class/Spec | Role | Key | iLvl | M+ Score | Status | Notes, gold headers,
rows tinted by status. Hover any row for full details.

🧙 **Know who you're inviting** — class-colored names, spec, item level, and
Mythic+ score (Blizzard rating, or Raider.IO automatically when installed).

🗝️ **Dungeon + key level** — each row shows the run it queued for
(e.g. `+5 AOF`), captured from your live listing and stored per entry.

🖱️ **One-click actions** — per-row whisper / invite / decline buttons plus a
right-click menu. Left-click whispers instantly.

🔎 **Filters + search + paging** — Status, Class and minimum-Key dropdowns,
search name/spec/dungeon/note, page through history with buttons or mouse
wheel. Auto-declines show their reason (`Declined (Low ILvl)`).

★ **Requirements + auto-decline** — set min item level / M+ score (sliders in
settings): qualifying rows turn green with a ★, and optional auto-decline
removes undergeared applicants for you (announced in chat, still logged).

📊 **Stats** — per-listing summary in chat on delist, plus `/lfgalert stats`
for all-time totals, accept rate, and accepted averages.

🔊 **Your sound, your way** — SoundKit ID presets, custom IDs, or your own
`.ogg`/`.mp3` file.

⚙️ **Full settings UI** — Esc → Options → AddOns → LFGAlert (or
`/lfgalert config`).

**Slash commands:** `/lfgalert show|clear|test|sound|soundfile|filter|
minilvl|minscore|autodecline|stats|window|open|config|debug`

**Notes & FAQ**

- Alerts fire only while **you** have an active listing (leader).
- Midnight hides listing/applicant text from addons: the addon strips those
  unreadable tokens and can use **your own keystone** for dungeon/key while
  pushing your key (toggleable in settings).
- No dependencies. Optional: Raider.IO for RIO scores.
- History and settings persist per account (up to 300 log rows, last
  30 listing sessions of stats).

## First-release changelog (v1.0.14)

- Sound + raid-warning + chat alert on new applications, leader-only
- Auto-opens Group Finder on the applicant list
- Blizzard-styled log: status/class/key filters, one-click row actions,
  status tints, decline reasons, hover tooltips
- Threshold highlights, optional auto-decline, session + all-time stats
- Custom sounds, minimap button, full settings UI

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
