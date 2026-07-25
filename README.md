# LifeOS


A personal, calendar-centric iOS app for tracking day-to-day life, game events, and entertainment progress — locally, without accounts or third-party sync.

LifeOS unifies IRL plans, gacha-game cadence (dailies, banners, patches), and reading/watching logs into one entry model with recurrence, completion tracking, customizable local notifications, and Markdown recap export.

> This is an early **v0.1** release. Core flows work; polish, sync, and deferred features are intentionally out of scope.

---

## Status

| Area | v0.1 |
|---|---|
| Unified entry model (IRL / Games / Entertainment) | Included |
| Day / Week / Month / Year calendar | Included |
| Recurrence + occurrence-level completion | Included |
| Local notification rules + presets | Included |
| Today inbox, search / filters, templates | Included |
| Markdown recap export | Included |

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

## What’s in v0.1

- **Calendar** — Day, Week, Month, Year views with category-aware styling  
- **Entries** — Single model covering IRL, games (GI / HSR / WuWa / Other), and entertainment  
- **Recurrence** — Daily, weekly (incl. weekday masks), monthly, every-N-months  
- **Completion** — Per-occurrence done state; quick-complete from rows  
- **Notifications** — Rule hub, presets, schedule-and-cancel planning (64 pending cap aware)  
- **Today inbox** — Open completable items and upcoming reminders  
- **Search & filters** — Title/notes search and category / game chips  
- **Templates & duplicate** — Starter patterns from Settings; duplicate from detail  
- **Export** — Date-range Markdown recap with stats (share or copy)  
- **Settings** — Export, templates, entry library, clear-all data  

---

## Testing

```bash
xcodegen generate
xcodebuild test \
  -scheme LifeOS \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Or in Xcode: **⌘U**.

v0.1 includes unit coverage for recurrence, entry capabilities, notification logic helpers, and recap export formatting.

---

## Project layout

```
LifeOS/
├── App/           App entry, SwiftData container
├── Models/        Entry, recurrence, notifications, progress, completions
├── Services/      RecurrenceEngine, NotificationPlanner, RecapExporter, templates
├── Views/         Calendar, entries, notifications, settings, export
├── Utilities/     Theme, filters, date helpers
└── Resources/     Assets (App Icon, AccentColor)
LifeOSTests/       Unit tests
project.yml        XcodeGen definition
```

---

## Design notes (v0.1)

- Dark theme only; neutral cool-gray accents  
- Local-only data — no backend, no account login  
- Entertainment logging is manual and notification-free by design  
- Game event data is manual (no unofficial account scrapers)

---

## License

Personal / private project unless otherwise stated.
