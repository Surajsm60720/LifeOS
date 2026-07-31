# LifeOS

**Version 1.0.1** · Released July 31, 2026  
*(App bundle `MARKETING_VERSION` remains **1.0** until the next Xcode release bump.)*

A personal, calendar-centric iOS app for tracking day-to-day life, game events, and entertainment progress — locally, without accounts or third-party sync.

LifeOS unifies IRL plans, gacha-game cadence (dailies, banners, patches), and reading/watching logs into one entry model with recurrence, completion tracking, customizable local notifications, hangout expense ledgers, multi-stop locations, Markdown recap export, full-app JSON backup/restore, optional Face ID app lock, a Dynamic Island Live Activity for today's events at a glance, and an **Ongoing Events** tab for multi-day windows.

> **v1.0.1** adds long-running event tracking and richer notification scheduling on top of the v1.0 local-first foundation. CloudKit sync, home-screen widgets, and charts remain intentionally out of scope.

---

## Status

| Area | v1.0 | v1.0.1 |
|---|---|---|
| Unified entry model (IRL / Games / Entertainment) | Included | — |
| All-day entries (date-only, no start time) | Included | — |
| Day / Week / Month / Year calendar | Included | — |
| Month heat grid + Year mini-month contribution maps | Included | — |
| Swipe complete / delete on Day, Week, Month rows | Included | — |
| Configurable default calendar view (Day default) | Included | — |
| Alternate app icons (Default / Geometric / Minimal) + light/dark appearances | Included | — |
| Live Activity / Dynamic Island (day-only, count + event list) | Included | — |
| Recurrence + occurrence-level completion | Included | — |
| Local notification rules + presets (64-cap aware) | Included | Enhanced |
| Notification budget (scheduled / remaining / firing today) | Included | — |
| Safe notification rule create (Save-only; draft-entry aware) | Included | — |
| Today inbox, search / filters, templates | Included | — |
| IRL multi-location + MapKit place search | Included | — |
| Hangout expense ledger (lines, totals, who owes you) | Included | — |
| Expense settlement share & clipboard copy | Included | — |
| Game event types (GI / HSR / WuWa) + Other session logs | Included | + In-Game Events |
| Entertainment progress + session targets | Included | — |
| Markdown recap export with stats | Included | — |
| JSON backup & restore (Replace or Merge) | Included | — |
| App Lock (Face ID / Touch ID / device passcode) | Included | — |
| Corrupted-store recovery mode + restore banner | Included | — |
| Haptic feedback across the app | Included | — |
| **Ongoing Events tab** (multi-day windows, start → end) | — | Included |
| **Extended entry duration** (days / weeks / months; end-date picker) | — | Included |
| **Date-based notifications** (specific date & time; relative to end) | — | Included |
| Calendar teaser → Ongoing tab | — | Included |

---

## Requirements

- macOS with **Xcode** (iOS 18.0+ deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to regenerate the project from `project.yml`)
- An Apple ID for device signing (Simulator works without a paid membership)
- A physical iPhone with Dynamic Island to try Live Activities end-to-end (Simulator support is limited)

---

## Stack

| Layer | Choice |
|---|---|
| Language / UI | Swift · SwiftUI (dark theme) |
| Persistence | SwiftData |
| Notifications | UserNotifications |
| Live Activities | ActivityKit · WidgetKit extension |
| Places | MapKit (`MKLocalSearch`) |
| Recurrence | Custom `Calendar` / `DateComponents` engine |
| Project generation | XcodeGen |

---

## Getting started

```bash
cd LifeOS
xcodegen generate   # if project.yml changed
open LifeOS.xcodeproj
```

1. Select the **LifeOS** scheme.
2. Choose an **iOS Simulator** or a connected device.
3. For a physical device: enable **Automatically manage signing** and select your Team (for both **LifeOS** and **LifeOSLiveActivityWidget**).
4. Run (**⌘R**).

Allow notification permission when prompted if you plan to use reminders.

---

## What's new in v1.0.1

### Ongoing Events tab

- New **Ongoing** tab between Calendar and Notifications for multi-day windows
- Any **non-recurring** entry with duration **≥ 24 hours** appears here automatically (banners, endgame phases, multi-day manga binges, etc.)
- Shows **Active Now**, **Starting Soon**, and collapsible **Recently Ended** sections with date range, progress bar, and days remaining
- Calendar still shows only the **start date** — Ongoing is where you track the full span
- Teaser card on the Calendar tab jumps to Ongoing when windows are active

### Extended duration

- Entry form supports **days, hours, and minutes** (up to 365 days) — no 24-hour cap
- Quick presets: **1h, 2d, 7d, 14d, 21d, 30d, 42d**
- All-day entries get an **Ends on** date picker
- Banner template pre-fills a 42-day all-day window

### Date-based notifications

- **Specific Date & Time** — one-shot reminder on an exact calendar date
- **Relative to End** — e.g. last day at 9 PM, or 1 day before the event ends
- New presets: **Last day reminder (9 PM)** and **1 day before end (9 PM)**
- Absolute-date rules schedule beyond the 7-day occurrence window (still respects the 64-notification cap)

### Game event types

- Added **In-Game Events** to the game event type picker (GI / HSR / WuWa)

### Notes

- **Recurring entries do not appear in Ongoing Events** — dailies, weeklies, and reset cadence stay in the calendar flow even if they have a long duration
- Recurring Spiral Abyss / Imaginary Theater-style setups remain calendar-only unless modeled as one-off windows

---

## What's new in v1.0

### First stable release

LifeOS v1.0 ships the full local-first calendar workflow: create entries, track recurrence and completions, get reminded, export recaps, and back up your library — all on-device with no account.

### App Lock

- **Settings → App Lock** — optional biometric or device-passcode lock when returning from background
- Full-screen lock overlay covers sheets so data stays hidden until you authenticate
- Face ID usage string included; works with Touch ID and passcode fallback

### All-day entries

- **All Day** toggle on the entry form — date-only events (e.g. daily leave) without a specific start time
- Calendar rows and detail views omit clock time for all-day items
- Recurrence and completion normalization respect day boundaries
- Round-trips through JSON backup

### Data resilience & backup hardening

- **Recovery store** — if the on-disk SwiftData store fails to open (corruption or migration issue), LifeOS launches in a degraded in-memory mode with a Settings banner pointing to Backup & Restore instead of crash-looping
- **Backward-compatible backups** — older backup files remain importable; only backups from a newer app version are rejected with a clear message
- Safer merge paths for duplicate notification rule IDs and unknown enum values from hand-edited files

### Performance & scale

- Recurrence expansion capped and pre-filtered for large libraries (10k+ entries)
- Cached occurrence counts in calendar views and Today inbox
- Lightweight notification candidate building before hitting the 64 pending cap
- Shared `@Query` across tabs to avoid redundant fetches

### Quality

- 58 automated unit tests including scale, backup integrity, and audit regression coverage
- Version string read from the app bundle in Settings (no hardcoded display version)
- Marketing version unified via `MARKETING_VERSION` in Xcode / `project.yml`

---

## What's in v0.7

Live Activity redesign, UX polish, haptics, and theming — see git history or prior README sections for detail. Highlights:

- Day-only Live Activity with Dynamic Island count badge and Lock Screen event list
- Duration editor with presets, improved location flow, richer notification rule display
- Unified accent tint and accessibility labels on calendar controls

---

## Testing

```bash
xcodegen generate
xcodebuild test \
  -scheme LifeOS \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Or in Xcode: **⌘U**.

Unit coverage includes recurrence, entry capabilities (incl. expense split), notification budget helpers, event window policy, recap export formatting, backup encode/decode + replace/merge, expense settlement text, scale/integrity harness, and audit regression tests. UI tests include a notification-banner icon smoke check (`LifeOSUITests`).

Live Activity UI, Dynamic Island expanded count, calendar swipe actions, App Lock, and year heat maps should be verified manually on a simulator or device.

---

## Project layout

```
LifeOS/
├── App/                 App entry, SwiftData container
├── LiveActivity/        Shared ActivityKit models, manager
├── LiveActivityWidget/  Dynamic Island / Lock Screen Live Activity UI (extension)
├── Models/              Entry, locations, expenses, recurrence, notifications, progress
├── Services/            Engine, planner, exporter, backup, expense share, templates, migrations
├── Views/               Calendar (incl. grid/swipe helpers), entries, ongoing events, notifications, settings, export / backup
├── Utilities/           Theme, filters, date helpers, event window policy, haptics, app lock
└── Resources/           Assets (App Icons + AccentColor)
LifeOSTests/             Unit tests
LifeOSUITests/           UI tests
project.yml              XcodeGen definition
```

---

## Design notes (v1.0.1)

- **Ongoing Events** lists one-off windows (duration ≥ 24h, no recurrence); calendar grid keeps start-day-only markers to avoid month clutter  
- **Recurring** game cadence (dailies, weeklies, abyss resets) stays in Calendar / Today — not duplicated in Ongoing  
- Dark theme only in-app; neutral cool-gray accents  
- App icons support system light/dark Home Screen appearances  
- Local-only data — no backend, no account login  
- Backup is device file share / import (JSON); Markdown recap is for LLM summaries only  
- Year activity heat is count-only (contribution-style), not category-colored  
- Calendar row swipes mirror Notifications hub motion (`List` swipeActions)  
- Live Activities are time-limited by iOS; reopening/foregrounding LifeOS re-syncs the snapshot  
- Dynamic Island expanded view shows only a count (no per-item list) to stay within the ~160pt system height budget  
- Lock Screen Live Activity shows up to 3 event rows with an overflow indicator  
- All-day entries store `startDate` at local midnight; no clock time shown in lists  
- App Lock engages on background when enabled; notification/Live Activity sync is deferred until unlock  
- Entertainment logging is manual and notification-free by design  
- Game event data is manual (no unofficial account scrapers)  
- Expense tracking is hangout-scoped (no dedicated Expenses tab); share text has no currency symbol yet  
- Haptic feedback uses `UIFeedbackGenerator` and `.sensoryFeedback` for tactile responses on key interactions  

---

## License

Personal / private project unless otherwise stated.
