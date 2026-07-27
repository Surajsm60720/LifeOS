# LifeOS

**Version 0.3**

A personal, calendar-centric iOS app for tracking day-to-day life, game events, and entertainment progress — locally, without accounts or third-party sync.

LifeOS unifies IRL plans, gacha-game cadence (dailies, banners, patches), and reading/watching logs into one entry model with recurrence, completion tracking, customizable local notifications, hangout expense ledgers, multi-stop locations, and Markdown recap export.

> This is an early **v0.3** release. Core flows work; polish, sync, and deferred features (CloudKit, widgets, charts) are intentionally out of scope.

---

## Status

| Area | v0.3 |
|---|---|
| Unified entry model (IRL / Games / Entertainment) | Included |
| Day / Week / Month / Year calendar | Included |
| Configurable default calendar view (Day default) | Included |
| Alternate app icons (Default / Geometric / Minimal) + light/dark appearances | Included |
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

---

## Stack

| Layer | Choice |
|---|---|
| Language / UI | Swift · SwiftUI (dark theme) |
| Persistence | SwiftData |
| Notifications | UserNotifications |
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
3. For a physical device: enable **Automatically manage signing** and select your Team.
4. Run (**⌘R**).

Allow notification permission when prompted if you plan to use reminders.

---

## What’s in v0.3

Everything from v0.2, plus:

- **Default calendar view** — App opens on **Day** by default; Settings → Calendar lets you choose Day / Week / Month / Year as the launch view  
- **App icons** — Three selectable styles in Settings → App Icon:
  - **Default** — playful illustrated calendar  
  - **Geometric** — modern geometric calendar  
  - **Minimal** — simple line-art calendar  
  Each icon includes light and dark appearance variants for Home Screen  
- **Icon change + notifications** — Switching icons clears delivered banners and reschedules pending reminders. Home Screen updates immediately. On **iOS 18**, Notification Center may keep the previous glyph until a **device restart** (known system cache limitation)

### Still included from earlier releases

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
- **Settings** — App icon, default calendar view, export, templates, entry library, clear-all data  

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

---

## Project layout

```
LifeOS/
├── App/           App entry, SwiftData container
├── Models/        Entry, locations, expenses, recurrence, notifications, progress
├── Services/      Engine, planner, exporter, templates, migrations
├── Views/         Calendar, entries, notifications, settings, export
├── Utilities/     Theme, filters, date helpers
└── Resources/     Assets (App Icons + AccentColor)
LifeOSTests/       Unit tests
LifeOSUITests/     UI tests
project.yml        XcodeGen definition
```

---

## Design notes (v0.3)

- Dark theme only in-app; neutral cool-gray accents  
- App icons support system light/dark Home Screen appearances  
- Local-only data — no backend, no account login  
- Entertainment logging is manual and notification-free by design  
- Game event data is manual (no unofficial account scrapers)  
- Expense tracking is hangout-scoped (no dedicated Expenses tab)

---

## License

Personal / private project unless otherwise stated.
