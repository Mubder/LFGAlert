# LFGAlert

WoW Retail addon (Midnight / 12.x): **sound alert + applicant log** for your Premade Group / Group Finder listings.

Inspired by **[Top] Party Alarm** (sound + raid-warning + chat message on new application), plus what it was missing:

- 🔊 Sound + center raid-warning + red chat message when someone signs up (leader only)
- 🪟 **Auto-opens Blizzard's Group Finder on your applicant list** on new queue (toggle: `/lfgalert window off`, manual: `/lfgalert open`; deferred until combat ends if you're fighting)
- 📝 Log of **who queued / was invited / accepted / declined / cancelled / timed out**
- 🪟 **Scrollable, sortable log window** — smooth mouse-wheel scrolling through the whole history (no paging), click any column header (Time / Applicant / Key / iLvl / M+ Score / Status) to sort, resizable from the bottom-right corner, remembers position / size / scale between sessions (`/lfgalert resetui` to reset)
- 🧙 Group-Finder-styled table: **Time | Applicant | Class/Spec | Role | Key | iLvl | M+ Score | Status | Notes** — gold headers, class icons + class-colored names, rows tinted by status (green invited/accepted, red declined, gold queued), fresh queues flash briefly, full detail in tooltip
- 🗝️ **Dungeon + key level per row** (e.g. `+5 AOF`) — captured from your live listing, stored per entry so it survives delists; also appended to chat lines (`[+5 AOF]`)
  - Midnight hides listing text from addons (`|Ku5|k` secrets): the addon sanitizes those, then falls back to **your own keystone** when pushing your key (toggle in Settings; tooltip marks it “your key”)
- 📣 Queue message shows the player's **role** (center banner + chat line)
  - Member data sometimes arrives seconds after the alert — the log **backfills** `?` rows automatically + retries
- 🧙 Every applicant row shows **class, spec, item level, M+ score**
  - M+ score = Blizzard `dungeonScore`; if **Raider.IO** is installed its score is preferred automatically
  - Hover a row for full tooltip (group members, note, scores)
- 🖱️ **One-click actions + right-click menu** — per-row whisper / invite / decline buttons (left-click = select row, right-click = full menu)
  - **Safety:** applicant IDs reset whenever you relist, so invite/decline-by-ID only act on rows from your *current* listing — old rows fall back to safe by-name invites and never decline the wrong person
- 🔎 Log **filters + text search** — Status, Class and minimum Key dropdowns plus search (name / spec / dungeon / note), one-click "Reset Filters"; auto-declines show the reason (`Declined (Low ILvl)`)
- 🔔 Sound ID **or custom sound file** (`/lfgalert soundfile <path>`)
- ★ **Highlight rules**: min item level / min M+ score (qualifying rows green + starred)
- ⛔ **Auto-decline** below your thresholds (OFF by default; only fires with real data, announced in chat, still logged — invite stragglers back via right-click → Invite)
- 📊 **Stats**: per-listing summary when you delist + `/lfgalert stats` (accept rate, accepted ilvl/M+ averages)
- ⚙️ Full settings UI (Esc → Options → AddOns → LFGAlert, or `/lfgalert config`): alerts, sound presets + custom file, window scale + reset, threshold sliders, auto-decline, stats with reset
- 🗺️ Minimap button: left-click opens log, right-click toggles sound, drag to move
- 🌍 Strings live in `Locales/enUS.lua` — ready for translations

## Install (manual)

1. Copy the `LFGAlert` folder (containing `LFGAlert.toc`, `Core.lua`, `LogFrame.lua`, `Options.lua`, `Locales/`) into:
   `World of Warcraft\_retail_\Interface\AddOns\`
2. Restart WoW / `/reload`. Enable “LFGAlert” in AddOns list if needed.
3. List a group in Group Finder (Premade Groups). When someone applies you get sound + warning + a log row.

## Commands

- `/lfgalert` / `/lfga show|hide|toggle` — applicant log window
- `/lfgalert clear` — wipe log history
- `/lfgalert test` — test sound + add sample row (try right-click on it)
- `/lfgalert sound [<id>]` — toggle sound or set sound ID (default `8959` = Raid Warning)
- `/lfgalert soundfile <path>|off` — custom sound file, e.g. `Interface\AddOns\LFGAlert\Sounds\alert.ogg` (`off` = back to ID)
- `/lfgalert minilvl <n>` — highlight min item level (`0` = off)
- `/lfgalert minscore <n>` — highlight min M+ score (`0` = off)
- `/lfgalert autodecline [on|off]` — auto-decline below thresholds (default OFF)
- `/lfgalert stats` — session + all-time summary
- `/lfgalert filter <all|queued|invited|accepted|declined|gone>` — filter log
- `/lfgalert window [on|off]` — auto-open Group Finder applicants on queue
- `/lfgalert open` — open Group Finder applicants now
- `/lfgalert resetui` — reset log window position / size / scale
- `/lfgalert on|off` — enable/disable

## Custom sounds

1. Put your file in the addon folder, e.g. `LFGAlert\Sounds\alert.ogg` (`.ogg` or `.mp3`).
2. Restart WoW so the client sees the new file, then either:
   - Settings → LFGAlert → check “Use custom sound file” and enter `Interface\AddOns\LFGAlert\Sounds\alert.ogg`, or
   - `/lfgalert soundfile Interface\AddOns\LFGAlert\Sounds\alert.ogg`
3. `/lfgalert test` to hear it.

## Notes

- Alerts only fire while **you have an active listing** (leader). Same rule as Top Party Alarm.
- History persists per account in `LFGAlertDB` (up to 300 entries).
- No dependencies. Optional: install **Raider.IO** for RIO scores.
- Retail API used: `C_LFGList.GetApplicants / GetApplicantInfo / GetApplicantMemberInfo / InviteApplicant / DeclineApplicant`, events `LFG_LIST_APPLICANT_LIST_UPDATED`, `LFG_LIST_APPLICANT_UPDATED`, `LFG_LIST_ACTIVE_ENTRY_UPDATE`.
- Dev: `luacheck .` (config in `.luacheckrc`, runs in CI via GitHub Actions).

## Files

- `LFGAlert.toc` — addon manifest (Interface 120005)
- `Locales/enUS.lua` — all user-facing strings (translation-ready)
- `Core.lua` — event tracking, alerts, log storage, slash commands
- `LogFrame.lua` — log window UI (scroll list, sorting, right-click menu, tooltips)
- `Options.lua` — minimap button + Settings panel
- `.pkgmeta` — CurseForge/Wago packager config (no externals)
- `LICENSE` — MIT

## Releasing on CurseForge

1. Commit, then tag: `git tag v1.0.15` + `git push --tags`.
2. With the BigWigs packager (GitHub action or CurseForge repo hook) watching the repo, the tag builds `LFGAlert.zip` from the `.toc` file list using `.pkgmeta` (`package-as: LFGAlert`, no libs).
3. Set the file's display name/changelog on CurseForge; `README.md` doubles as the project description.
