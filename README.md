# LifeOS

**Version 0.4**

A personal, calendar-centric iOS app for tracking day-to-day life, game events, and entertainment progress — locally, without accounts or third-party sync.

LifeOS unifies IRL plans, gacha-game cadence (dailies, banners, patches), and reading/watching logs into one entry model with recurrence, completion tracking, customizable local notifications, hangout expense ledgers, multi-stop locations, Markdown recap export, and a Dynamic Island Live Activity for remaining to-dos.

> This is an early **v0.4** release. Core flows work; polish, sync, and deferred features (CloudKit, home-screen widgets, charts) are intentionally out of scope.

---

## Status

| Area | v0.4 |
|---|---|
| Unified entry model (IRL / Games / Entertainment) | Included |
| Day / Week / Month / Year calendar | Included |
| Configurable default calendar view (Day default) | Included |
| Alternate app icons (Default / Geometric / Minimal) + light/dark appearances | Included |
| Live Activity / Dynamic Island (Day–Year remaining to-dos) | Included |
| Recurrence + occurrence-level completion | Included |
| Local notification rules + presets (64-cap aware) | Included |
| Today inbox, search / filters, templates | Included |
| IRL multi-location + MapKit place search | Included |
| Hangout expense ledger (lines, totals, who owes you) | Included |
| Game event types (GI / HSR / WuWa) + Other session logs | Included |
| Entertainment progress + session targets | Included |
| Markdown recap export with stats | Included |

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
| Live Activities | ActivityKit · WidgetKit extension · App Intents |
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

## What’s in v0.4

Everything from v0.3, plus:

- **Live Activity (Dynamic Island)** — Optional in Settings → Dynamic Island. When enabled, LifeOS shows a compact remaining-count pulse on the Dynamic Island / Lock Screen  
- **Expanded island container** — Hold the Live Activity to see:
  - Day / Week / Month / Year scope buttons (switch **without opening the app**)  
  - Up to **8** open completable items (`isCompletable && !isCompleted`)  
  - Footer when more exist: `...N more for this day/week/month/year — open LifeOS`  
- **Kept in sync** — Snapshot refreshes on enable/disable, default-scope change, completion toggles, app launch, and foreground  

### Still included from earlier releases

- **Default calendar view** — App opens on **Day** by default; Settings → Calendar lets you choose Day / Week / Month / Year as the launch view  
- **App icons** — Three selectable styles in Settings → App Icon (Default / Geometric / Minimal), each with light and dark Home Screen appearances  
- **Icon change + notifications** — Switching icons clears delivered banners and reschedules pending reminders. On **iOS 18**, Notification Center may keep the previous glyph until a **device restart**  
- **Calendar** — Day, Week, Month, Year with category-aware styling  
- **Entries** — Unified model for IRL, games (GI / HSR / WuWa / Other), and entertainment  
- **Recurrence** — Daily, weekly (weekday masks), monthly, every-N-months  
- **Completion** — Per-occurrence done state; quick-complete from rows / Today inbox  
- **Notifications** — Hub, presets, schedule-and-cancel planner (64 pending cap), test notification  
- **Today inbox** — Open completable items and upcoming reminders  
- **Search & filters** — Text search plus category / game chips  
- **IRL locations** — Multi-stop places with MapKit search (name + coordinates)  
- **Hangout expenses** — Freestyle line items + total; optional “who owes you”; equal split helper; mutually exclusive with recurrence; cleared on duplicate  
- **Game event types** — Taxonomy for primary games; Other games use session logs (planned activity / played with)  
- **Entertainment** — Progress tracking, optional session targets, display-only recurrence, no notifications  
- **Templates & duplicate** — Built-in starters from Settings; duplicate from detail  
- **Export** — Date-range Markdown recap with spend, event-type, and progress stats  
- **Settings** — App icon, default calendar view, Live Activity, export, templates, entry library, clear-all data  

---

## Testing

```bash
xcodegen generate
xcodebuild test \
  -scheme LifeOS \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Or in Xcode: **⌘U**.

Unit coverage includes recurrence, entry capabilities (incl. expense split), notification logic helpers, and recap export formatting. UI tests include a notification-banner icon smoke check (`LifeOSUITests`).

Live Activity UI and Dynamic Island scope switching should be verified manually on a real device.

---

## Project layout

```
LifeOS/
├── App/                 App entry, SwiftData container
├── LiveActivity/        Shared ActivityKit models, manager, LiveActivityIntent
├── LiveActivityWidget/  Dynamic Island / Lock Screen Live Activity UI (extension)
├── Models/              Entry, locations, expenses, recurrence, notifications, progress
├── Services/            Engine, planner, exporter, templates, migrations
├── Views/               Calendar, entries, notifications, settings, export
├── Utilities/           Theme, filters, date helpers
└── Resources/           Assets (App Icons + AccentColor)
LifeOSTests/             Unit tests
LifeOSUITests/           UI tests
project.yml              XcodeGen definition
```

---

## Design notes (v0.4)

- Dark theme only in-app; neutral cool-gray accents  
- App icons support system light/dark Home Screen appearances  
- Local-only data — no backend, no account login  
- Live Activities are time-limited by iOS; reopening/foregrounding LifeOS re-syncs the snapshot  
- Dynamic Island interactivity is limited to App Intents (scope switching); deep lists still live in the app  
- Entertainment logging is manual and notification-free by design  
- Game event data is manual (no unofficial account scrapers)  
- Expense tracking is hangout-scoped (no dedicated Expenses tab)

---

## License

Personal / private project unless otherwise stated.
