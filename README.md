# LifeOS

**Version 0.7**

A personal, calendar-centric iOS app for tracking day-to-day life, game events, and entertainment progress — locally, without accounts or third-party sync.

LifeOS unifies IRL plans, gacha-game cadence (dailies, banners, patches), and reading/watching logs into one entry model with recurrence, completion tracking, customizable local notifications, hangout expense ledgers, multi-stop locations, Markdown recap export, full-app JSON backup/restore, and a Dynamic Island Live Activity for today's events at a glance.

> This is an early **v0.7** release. Core flows work; polish, sync, and deferred features (CloudKit, home-screen widgets, charts) are intentionally out of scope.

---

## Status

| Area | v0.7 |
|---|---|
| Unified entry model (IRL / Games / Entertainment) | Included |
| Day / Week / Month / Year calendar | Included |
| Month heat grid + Year mini-month contribution maps | Included |
| Swipe complete / delete on Day, Week, Month rows | Included |
| Configurable default calendar view (Day default) | Included |
| Alternate app icons (Default / Geometric / Minimal) + light/dark appearances | Included |
| Live Activity / Dynamic Island (day-only, count + event list) | Included |
| Recurrence + occurrence-level completion | Included |
| Local notification rules + presets (64-cap aware) | Included |
| Notification budget (scheduled / remaining / firing today) | Included |
| Safe notification rule create (Save-only; draft-entry aware) | Included |
| Today inbox, search / filters, templates | Included |
| IRL multi-location + MapKit place search | Included |
| Hangout expense ledger (lines, totals, who owes you) | Included |
| Expense settlement share & clipboard copy | Included |
| Game event types (GI / HSR / WuWa) + Other session logs | Included |
| Entertainment progress + session targets | Included |
| Markdown recap export with stats | Included |
| JSON backup & restore (Replace or Merge) | Included |
| Haptic feedback across the app | Included |

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

## What's new in v0.7

### Live Activity / Dynamic Island redesign

- **Day-only scope** — The Live Activity now always tracks today; the Week/Month/Year scope switcher has been removed for a simpler, faster-to-read experience
- **Dynamic Island (expanded)** — Long-pressing shows a clean count badge ("4 — Remaining today") instead of a per-item list, avoiding the ~160pt height budget that caused clipped/garbled rendering in v0.6
- **Lock Screen Live Activity** — Compact card showing up to 3 events with color dots and a "+N more events" overflow line; reduced fonts/spacing so the card never clips at the edges
- **All events for the day** — The Live Activity now shows every entry occurring today (not just completable to-dos); completed items drop off automatically
- **Stable row identities** — `LiveActivityItem` uses UUID instead of title, preventing ForEach collisions when two entries share a name

### UX & form improvements

- **Search & Filter bar** — "Search & Filter" header with magnifying glass icon, "Clear all" button, "Filter by category" label, broader placeholder ("Search titles, notes, places…"), and a bordered/padded card style
- **Duration editor** — Hours/minutes steppers with quick-pick presets (5m–120m) replace the old single-stepper + text field
- **Category sections** — Game and Entertainment pickers are in their own sections (no more "Category Details" header)
- **Location flow** — "Add Location" opens the Place Search sheet immediately; each location row has a "Change Place" and "Remove" button; "Pinned" renamed to "On map" with a map-pin icon
- **Add-action buttons** — "Add Expense Line", "Add Person Who Owes You", "Add Notification Rule", "Add Progress Tracking", and "Add Location" now use a consistent bold+icon style (`addActionButton`)
- **Progress label** — Placeholder changed to "Counting by (e.g. episode, chapter, page)" with an explanatory footer
- **Recurrence header** — Entertainment entries now show "Repeat Schedule" (not "Personal Habit (Display Only)") with a clarifying footer

### Notification & detail enhancements

- **Richer notification rule display** — Entry detail and form both show `triggerSummary`, `detailLines` (timing behavior, recurrence, completion needs), and `renderedMessage`
- **Notification button contrast** — "Create Notification Rule" uses `.bordered` instead of `.borderedProminent`
- **Recurrence summaries** — `RecurrenceRule.summaryDescription` provides human-readable schedules ("Weekly · Mon, Wed · 10 occurrences")

### Haptic feedback

- Selection haptics on progress steppers and recurrence day-picker
- Light haptics on Cancel, Edit, Done buttons
- Medium haptic on the "+" (Add Entry) button
- Success haptic on Save

### Theming & consistency

- **Unified accent tint** — `LifeOSTheme.accent` applied app-wide via `.tint()` on the root `ContentView`, entry sheets, detail views, settings, and notification forms
- **Accessibility** — Calendar navigation buttons and filter button now carry accessibility labels

### Settings

- **Default Scope picker removed** — Settings no longer has a "Default Scope" option for Live Activities (always Day)
- **Updated footer** — Dynamic Island section footer reflects the day-only design

---

## What's in v0.6

Everything from v0.5, plus calendar and notification UX polish:

- **Month calendar** — Heat-styled day cells (density vs month peak), category capsules, completion ticks, clearer selected-day panel  
- **Year calendar** — Fixed-size mini-month grids (6×7) with GitHub-style contribution heat by daily event count (`None → 1–2 → 3 → 4 → 5 → 6+`); no category tint on days  
- **Swipe actions** — On Day, Week, and Month entry rows (same native `List` swipe feel as Notifications): swipe left to complete / undo, swipe right to delete (with confirmation). Non-completable entries show an alert instead of completing  
- **Notification rule create** — Adding a rule from New Entry no longer attaches a default rule before you confirm. The editor opens against the draft entry; presets and custom triggers only persist on **Save**. Cancel leaves the entry unchanged  

### Still included from earlier releases

- **JSON backup & restore** — Settings → Backup & Restore; Replace All or Merge by entry ID  
- **Notification budget** — Scheduled / Remaining / Firing Today against the iOS 64 pending cap  
- **Expense settlement share** — Share or copy plain-text hangout breakdowns  
- **Default calendar view** — Day by default; Settings → Calendar for Day / Week / Month / Year  
- **App icons** — Default / Geometric / Minimal with light and dark appearances  
- **Calendar** — Day, Week, Month, Year with category-aware styling  
- **Entries** — Unified model for IRL, games (GI / HSR / WuWa / Other), and entertainment  
- **Recurrence** — Daily, weekly (weekday masks), monthly, every-N-months  
- **Completion** — Per-occurrence done state; quick-complete from rows / Today inbox  
- **Notifications** — Hub, presets, schedule-and-cancel planner (64 pending cap), test notification  
- **Today inbox** — Open completable items and upcoming reminders  
- **Search & filters** — Text search plus category / game chips  
- **IRL locations** — Multi-stop places with MapKit search  
- **Hangout expenses** — Line items, settlements, equal split; exclusive with recurrence  
- **Game event types** — Taxonomy for primary games; Other games use session logs  
- **Entertainment** — Progress tracking, optional session targets, no notifications  
- **Templates & duplicate** — Built-in starters; duplicate from detail  
- **Export** — Date-range Markdown recap for LLM summaries  
- **Settings** — App icon, calendar default, Live Activity, recap, backup/restore, templates, library, clear-all  

---

## Testing

```bash
xcodegen generate
xcodebuild test \
  -scheme LifeOS \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Or in Xcode: **⌘U**.

Unit coverage includes recurrence, entry capabilities (incl. expense split), notification budget helpers, recap export formatting, backup encode/decode + replace/merge, and expense settlement text. UI tests include a notification-banner icon smoke check (`LifeOSUITests`).

Live Activity UI, Dynamic Island expanded count, calendar swipe actions, and year heat maps should be verified manually on a simulator or device.

---

## Project layout

```
LifeOS/
├── App/                 App entry, SwiftData container
├── LiveActivity/        Shared ActivityKit models, manager
├── LiveActivityWidget/  Dynamic Island / Lock Screen Live Activity UI (extension)
├── Models/              Entry, locations, expenses, recurrence, notifications, progress
├── Services/            Engine, planner, exporter, backup, expense share, templates, migrations
├── Views/               Calendar (incl. grid/swipe helpers), entries, notifications, settings, export / backup
├── Utilities/           Theme, filters, date helpers, haptics
└── Resources/           Assets (App Icons + AccentColor)
LifeOSTests/             Unit tests
LifeOSUITests/           UI tests
project.yml              XcodeGen definition
```

---

## Design notes (v0.7)

- Dark theme only in-app; neutral cool-gray accents  
- App icons support system light/dark Home Screen appearances  
- Local-only data — no backend, no account login  
- Backup is device file share / import (JSON); Markdown recap is for LLM summaries only  
- Year activity heat is count-only (contribution-style), not category-colored  
- Calendar row swipes mirror Notifications hub motion (`List` swipeActions)  
- Live Activities are time-limited by iOS; reopening/foregrounding LifeOS re-syncs the snapshot  
- Dynamic Island expanded view shows only a count (no per-item list) to stay within the ~160pt system height budget  
- Lock Screen Live Activity shows up to 3 event rows with an overflow indicator  
- Entertainment logging is manual and notification-free by design  
- Game event data is manual (no unofficial account scrapers)  
- Expense tracking is hangout-scoped (no dedicated Expenses tab); share text has no currency symbol yet  
- Haptic feedback uses `UIFeedbackGenerator` and `.sensoryFeedback` for tactile responses on key interactions  

---

## License

Personal / private project unless otherwise stated.
