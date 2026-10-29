# LifeOS

**Version 1.0.4** · Released October 29, 2026

A personal, calendar-centric iOS app for tracking day-to-day life, game events, and entertainment progress — locally, without accounts or third-party sync.

LifeOS unifies IRL plans, gacha-game cadence (dailies, banners, patches), and reading/watching logs into one entry model with recurrence, completion tracking, customizable local notifications, hangout expense ledgers, multi-stop locations with a map picker, Markdown recap export, weekly automatic backups plus monthly/yearly archive exports to a folder outside the app, optional Face ID app lock, and an **Ongoing Events** tab for multi-day windows and the current weekly or monthly cycle (this occurrence through the next).

> **v1.0.4** retires the Dynamic Island Live Activity, trims pity counters to just the number and the guarantee state, and adds **Automatic Backup** — weekly full-restore snapshots plus monthly and yearly archive exports, written to a folder you choose in Files so they survive the app being deleted. CloudKit sync, home-screen widgets, and charts remain intentionally out of scope.

---

## Status

| Area | v1.0 | v1.0.1 | v1.0.2 | v1.0.3 | v1.0.4 |
|---|---|---|---|---|---|
| Unified entry model (IRL / Games / Entertainment) | Included | — | — | — | — |
| All-day entries (date-only, no start time) | Included | — | — | — | — |
| Day / Week / Month / Year calendar | Included | — | — | — | — |
| Month heat grid + Year mini-month contribution maps | Included | — | — | — | — |
| Swipe complete / delete on Day, Week, Month rows | Included | — | — | — | — |
| Configurable default calendar view (Day default) | Included | — | — | — | — |
| Alternate app icons (Default / Geometric / Minimal) + light/dark appearances | Included | — | — | — | — |
| ~~Live Activity / Dynamic Island~~ (removed in v1.0.4) | Included | — | — | — | Removed |
| Recurrence + occurrence-level completion | Included | — | — | — | — |
| Local notification rules + presets (64-cap aware) | Included | Enhanced | — | — | — |
| Notification budget (scheduled / remaining / firing today) | Included | — | — | — | — |
| Safe notification rule create (Save-only; draft-entry aware) | Included | — | — | — | — |
| Today inbox, search / filters, templates | Included | — | — | — | — |
| IRL multi-location + MapKit place search | Included | — | Map picker + live preview | — | — |
| Hangout expense ledger (lines, totals, who owes you) | Included | — | — | — | — |
| Expense settlement share & clipboard copy | Included | — | — | — | — |
| Game event types (GI / HSR / WuWa) + Other session logs | Included | + In-Game Events | — | — | — |
| Entertainment progress + session targets | Included | — | — | — | — |
| Markdown recap export with stats | Included | — | — | — | — |
| JSON backup & restore (Replace or Merge) | Included | — | — | — | — |
| App Lock (Face ID / Touch ID / device passcode) | Included | — | — | — | Face ID fixed |
| Corrupted-store recovery mode + restore banner | Included | — | — | — | — |
| Haptic feedback across the app | Included | — | — | — | — |
| **Ongoing Events tab** (multi-day windows, start → end) | — | Included | + occurrence-cycle cadence | — | — |
| **Extended entry duration** (days / weeks / months; end-date picker) | — | Included | — | — | — |
| **Date-based notifications** (specific date & time; relative to end) | — | Included | — | — | — |
| Calendar teaser → Ongoing tab | — | Included | — | — | — |
| **Pity counters** (GI / HSR / WuWa banners, +1/+10, 50/50) | — | — | — | Included | — |
| **Automatic weekly backup** to a user-chosen folder (outside the app) | — | — | — | — | Included |
| **Monthly & yearly archive exports** (period JSON for LLM recaps) | — | — | — | — | Included |
| **Manual "Back Up Now" snapshot** (own rotation, never evicts weeklies) | — | — | — | — | Included |

---

## Requirements

- macOS with **Xcode** (iOS 18.0+ deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to regenerate the project from `project.yml`)
- An Apple ID for device signing (Simulator works without a paid membership)
- An iPhone or iPad; automatic backups can target iCloud Drive, so iCloud must be signed in for off-device copies

---

## Stack

| Layer | Choice |
|---|---|
| Language / UI | Swift · SwiftUI (dark theme) |
| Persistence | SwiftData |
| Notifications | UserNotifications |
| Background work | BackgroundTasks (`BGAppRefreshTask`) |
| Backup destination | Security-scoped folder bookmark (`UIDocumentPicker`) |
| Places | MapKit (search + map picker) |
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
3. For a physical device: enable **Automatically manage signing** and select your Team.
4. Run (**⌘R**).

Allow notification permission when prompted if you plan to use reminders.

---

## What's new in v1.0.4

### Automatic backups

- **Settings → Automatic Backup** lets you pick any folder through the Files picker — ideally a dedicated folder in iCloud Drive, outside the app
- **Weekly backups** (`LifeOS-Weekly-yyyy-MM-dd-HHmm.json`) are complete restore points: every entry, expense, location, recurrence, notification rule, progress record, completion, and pity counter. The newest 12 are kept (about three months), and any one of them restores everything
- **Monthly archives** (`LifeOS-Month-yyyy-MM.json`) cover the 1st through the last day of each month; the newest 24 are kept
- **Yearly archives** (`LifeOS-Year-yyyy.json`) cover 1 January through 31 December; the newest 10 are kept
- Archives are flat JSON rows shaped for an LLM recap ("how did my month/year go"). Recurring entries are materialized per occurrence, so a daily shows up as ~30 dated rows. They are **not** importable as backups — the distinct `lifeos.recap` format makes Replace/Merge reject them
- Archives run after the period ends, on the first day of the next period at the shared time. Enabling one for the first time writes the last completed month/year; later enablements catch up missed periods (capped)
- The check runs on launch, foreground, background, and an opportunistic `BGAppRefreshTask`, so a missed slot is caught up the next time the app runs
- **Back Up Now** writes a complete snapshot with its own `LifeOS-Manual-` prefix, so pressing it repeatedly can never rotate away a weekly restore point
- A folder inside the app's own sandbox is rejected at pick time, since it would still be destroyed with the app; removing a folder turns every schedule off
- Manual **Export Backup** / **Import Backup** are unchanged

An archive is self-describing, so an LLM needs no instructions beyond "summarize this month/year":

```json
{
  "format": "lifeos.recap",
  "version": 1,
  "kind": "month",
  "label": "2026-09",
  "periodStart": "2026-09-01",
  "periodEnd": "2026-09-30",
  "totals": { "events": 42, "completed": 31, "byCategory": { "Games": 30 }, "expenseTotal": 120 },
  "entries": [
    {
      "date": "2026-09-01",
      "title": "Dailies",
      "category": "Games",
      "subCategory": "Genshin Impact",
      "eventType": "Dailies",
      "completed": true
    }
  ]
}
```

### Dynamic Island removed

- The Live Activity, its widget extension target, the Settings toggle, and every sync call site are gone
- `NSSupportsLiveActivities` is no longer declared

### Pity counters simplified

- Dropped the "who did you get?" prompt and the last-5★ name/pity storage (`lastDropName`, `lastDropPity`, `lastDropAt`, `lastDropWasFeatured`)
- Cards now show **when the counter was last updated** instead of the last drop
- The Featured / Off-banner prompt is still there — it is what drives guaranteed and fate-point state

### App Lock fixed

- `NSFaceIDUsageDescription` was missing from `Info.plist`, so iOS never granted Face ID to the app and every unlock fell back to the passcode sheet — even on Face ID devices
- The declaration is present now; the first unlock after installing asks for Face ID permission, and the app appears under **Settings → Face ID & Passcode → Other Apps**
- Biometry naming performs the silent capability check before reading `LAContext.biometryType`, so Settings and the lock screen say **Face ID** with the face icon instead of **Passcode** with a shield
- `LAError` failures now name the setting that fixes them (Face ID denied for the app, not enrolled, locked out) instead of "Biometry is not available."
- Passcode fallback is still deliberate: a failed or unavailable scan can never lock you out of your own data

### Things to know

- **Weekly is the restore point.** Monthly and yearly files are summaries; Replace/Merge rejects them, and deleting the weekly files leaves nothing restorable
- **iOS decides when background work actually runs.** Treat the slot as a target rather than a guarantee — opening the app always performs the catch-up
- **Re-link the folder after a reinstall.** Files survive deleting the app; the security-scoped bookmark does not. Pick the same folder once and the schedule resumes
- **The destination must be reachable.** A failed write (offline, iCloud folder not downloaded, permission revoked) is retried after 30 minutes instead of on every foreground
- **Old `LifeOS-Auto-*` files** from 1.0.3 and earlier are no longer produced or pruned; delete them once the new `LifeOS-Weekly-*` files exist
- **Catch-up is bounded** to 12 months and 5 years per run, so a long gap fills in over a few launches
- **First enable writes only the last completed period** — an empty history before that is intentional
- **Removed pity data is gone.** The last-5★ name, pity, and date were dropped from the model; older backups still import, with those fields ignored
- **Live Activity is retired.** Any activity still on the Lock Screen ends when the app is updated, since the extension no longer exists

### Notes

- Marketing version is **1.0.4** (`CURRENT_PROJECT_VERSION` 4)
- Backups written by 1.0.3 and earlier still decode; the removed pity fields are simply ignored

---

## What's new in v1.0.3

### Pity counters

- **Settings → Games → Pity Counters** — one sheet with all three gacha titles and their banner types
- Seeded banners: Genshin character / weapon / standard; Star Rail character / light cone / standard; WuWa resonator / featured weapon / standard convenes
- **+1 / +10 / −1 / −10** for a live pull session, plus **Got 5★** (asks Featured vs Lost 50/50 when it matters; guaranteed and always-guaranteed banners just reset)
- Long-press a card to move it up or down within that game
- After Got 5★ you can optionally name who you got — only the last 5★ is kept per banner
- Cards heat up through approaching → soft pity → hard pity → over pity
- Add your own banner type (new selectors / anniversary banners) without a catalog change
- Counters are their own SwiftData store — pity is not tied to calendar Banner Window entries, so it survives a patch rotation
- Included in JSON backup / restore and wiped with Delete All Data (official banners re-seed empty)

### Notes

- Marketing version is **1.0.3** (`CURRENT_PROJECT_VERSION` 3)
- Chronicled Wish and WuWa standard character convene are not seeded; add them from the sheet if you need them

---

## What's new in v1.0.2

### Map-first location picker

- **Add Location** opens a map where you can search with suggestions, tap to drop a pin, or use your current location
- Reverse-geocoding fills the place name after a pin drop; you can still type a name with no pin
- Entry form and detail show a live MapKit thumbnail when a place has coordinates (nothing extra is stored — name + lat/long only)

### Current-period cadence in Ongoing Events

- Weekly recurrence appears in **Active Now** from this occurrence through the next (e.g. Wed → next Wed)
- Monthly / every-N-months uses the same cycle (e.g. 16 Aug → 16 Sep) — never a separate upcoming next month
- Dailies stay out of Ongoing so the tab does not flood
- Completable current-period items stay in Active Now with a **Done** badge after every occurrence in the period is marked complete
- One-off windows (duration ≥ 24h, no recurrence) are unchanged, including Starting Soon and Recently Ended

### Notes

- `isEventWindow` is still one-off-only, so relative-to-end notifications do not attach to weeklies/monthlies
- Marketing version is **1.0.2** (`CURRENT_PROJECT_VERSION` 2)
- Unit tests: 75, including current-period Ongoing coverage

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

Unit coverage includes recurrence, entry capabilities (incl. expense split), notification budget helpers, event window policy (including occurrence-cycle cadence), recap export formatting, backup encode/decode + replace/merge, automatic-backup scheduling/retention, archive period math and archive-vs-backup format separation, expense settlement text, scale/integrity harness, audit regression tests, and pity-counter rules. UI tests include a notification-banner icon smoke check (`LifeOSUITests`).

Calendar swipe actions, App Lock, the folder picker, and year heat maps should be verified manually on a simulator or device.

---

## Project layout

```
LifeOS/
├── App/                 App entry, SwiftData container
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

## Design notes (v1.0.4)

- **Pity counters** live under Settings, not a fifth tab; they are banner-type rows (not calendar Banner Window entries) so pity survives a patch rotation
- Cards heat from the game accent into orange/red as you enter approaching, soft pity, hard pity, and over pity
- **Ongoing Events** lists one-off windows (duration ≥ 24h, no recurrence) plus the current weekly/monthly **cycle** (this occurrence through the next)  
- **Dailies** stay in Calendar / Today — not duplicated in Ongoing  
- Cadence items never appear in Starting Soon or Recently Ended  
- Place picker is map-first; location rows use a live MapKit preview, not a stored screenshot  
- Dark theme only in-app; neutral cool-gray accents  
- App icons support system light/dark Home Screen appearances  
- Local-only data — no backend, no account login  
- Backup is device file share / import (JSON); Markdown recap is for LLM summaries only
- **Automatic backups** live outside the app container. The user picks a folder once through the Files picker; LifeOS keeps a security-scoped bookmark and writes weekly snapshots, monthly archives, and yearly archives there, each with its own prefix and retention
- **Retention is a count, not an age**: the 13th weekly file deletes the oldest weekly file. A snapshot is never removed for being older than three months
- Archives are *not* backups. They use a separate `lifeos.recap` format so `BackupService.decode` rejects them, because restoring one would delete everything outside its window
- The schedule is a *slot*, not a timer — iOS gives no reliable timer, so the due-check runs on launch, foreground, background, and an opportunistic `BGAppRefreshTask`
- A folder inside the app sandbox is rejected at pick time, because it would be deleted along with the app
- Pity counters no longer store the last 5★ name or the pity it landed at; the card shows the last time the counter was touched instead  
- Year activity heat is count-only (contribution-style), not category-colored  
- Calendar row swipes mirror Notifications hub motion (`List` swipeActions)  
- All-day entries store `startDate` at local midnight; no clock time shown in lists  
- App Lock engages on background when enabled; notification sync is deferred until unlock (backups are not, since they never reach the UI)  
- Face ID is withheld by iOS without `NSFaceIDUsageDescription`; because the lock uses `.deviceOwnerAuthentication`, the failure surfaces as a silent passcode fallback rather than an error, so the usage string is a hard requirement, not a nicety  
- Entertainment logging is manual and notification-free by design  
- Game event data is manual (no unofficial account scrapers)  
- Expense tracking is hangout-scoped (no dedicated Expenses tab); share text has no currency symbol yet  
- Haptic feedback uses `UIFeedbackGenerator` and `.sensoryFeedback` for tactile responses on key interactions  

---

## License

Personal / private project unless otherwise stated.
