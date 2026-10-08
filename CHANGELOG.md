# LFGAlert 1.2.0

## New

- **Sound by role** - Tank, Healer and DPS each play their own alert sound, so you hear who signed up without looking. Defaults: Tank = troll male cheer, Healer = troll male cheer (second line), DPS = dracthyr cheer. Set your own IDs in Settings (Sound by role - typed IDs also save when you click away, and a click-to-preview gallery shows IDs on the buttons) or with `/lfgalert rolesound tank|healer|dps <id>|off` (off = use the global sound). Browse more IDs at wowhead.com/sounds and preview any of them with `/run PlaySound(<id>)`. Combine with the per-role gates to fine-tune exactly what each role triggers.

# LFGAlert 1.1.1

Big alert upgrade plus a batch of reliability fixes for the applicant alerts.

## New

- **Rich on-screen applicant alert** - the center alert now shows the applicant's name, role icon (Tank / Healer / DPS) and spec in class colors, e.g. "New applicant: Thraex - [tank icon] Tank Protection Warrior".
- **Stacked alerts** - when several players sign up at once, every applicant gets their own line at the top of the screen (up to 5 at a time). Blizzard's raid warning only holds 2 messages and silently dropped the rest.
- **Per-role alert gates** - sound, chat message, screen toast and the Group Finder popup can each be enabled/disabled per role (tank / healer / DPS) in the settings panel.
- **Master mute** - silence every alert while applicants still get logged.
- **Group by keystone** - the applicant log can group rows under their keystone level (on by default).
- **Custom addon icon** - new icon across the addon list, CurseForge, the minimap button and the log window title.
- **Alert tracing** - `/lfgalert trace` prints per-applicant alert decisions for diagnosis.

## Fixed

- No more **re-alert storm on login or reload** while you have an active listing: applicants who queued before the reload are remembered - no duplicate sounds, toasts, popups or log rows, and invite/decline buttons keep working on their rows.
- **Simultaneous applicants no longer lose their alerts** - applicants whose data arrives late from Blizzard are no longer silently dropped, and everyone gets the same rich alert style (the addon briefly waits for the applicant's data before alerting).
- **Role icons render again** on Midnight clients (both modern atlas and classic icon markup supported, with a built-in fallback).
- The sound no longer plays for applicants who cancel again within a second or two of applying.

For the full command list: `/lfgalert`.
