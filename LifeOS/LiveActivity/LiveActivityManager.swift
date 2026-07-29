import ActivityKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class LiveActivityManager {
    static let enabledStorageKey = "liveActivityEnabled"

    /// Live Activities render as fixed, non-scrolling snapshots, so the content payload
    /// only ever needs enough rows to cover the largest surface (Lock Screen).
    static let maxDisplayedItems = 8

    static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledStorageKey)
    }

    /// Computes today's content state using current SwiftData models.
    /// The Live Activity always tracks "today" — no Week/Month/Year switching —
    /// to keep the Dynamic Island and Lock Screen experience simple and fast to read.
    static func snapshot(
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) -> LifeOSLiveActivityAttributes.ContentState {
        let descriptor = FetchDescriptor<Entry>()
        let entries = (try? modelContext.fetch(descriptor)) ?? []

        let now = Date()
        let interval = DateInterval(start: DateFormatting.startOfDay(now, calendar: calendar), duration: 86_400)

        // Every entry happening today, not just completable to-dos — a finished to-do
        // drops off the list once it's checked off, everything else (including plain
        // calendar events with no completion tracking) stays visible all day.
        let occurrences = RecurrenceEngine.shared.expandEntries(entries, in: interval, calendar: calendar)
        let visible = occurrences.filter { occ in
            !(occ.entry.isCompletable && occ.entry.isCompleted(on: occ.occurrenceDate, calendar: calendar))
        }
        let sorted = visible.sorted { a, b in
            if a.occurrenceDate != b.occurrenceDate {
                return a.occurrenceDate < b.occurrenceDate
            }
            return a.entry.title.localizedCaseInsensitiveCompare(b.entry.title) == .orderedAscending
        }

        // Dynamic Island / Lock Screen Live Activities cannot scroll, so we only ever
        // hand over as many rows as the widget will actually lay out at once.
        let items = sorted.prefix(LiveActivityManager.maxDisplayedItems).map { occ in
            let fallbackHex = "C8CCD4"
            let derivedHex = occ.entry.displayColor.hexString ?? fallbackHex
            let colorHex = occ.entry.colorOverrideHex ?? derivedHex
            return LiveActivityItem(title: occ.entry.title, colorHex: colorHex)
        }

        return LifeOSLiveActivityAttributes.ContentState(
            itemCount: sorted.count,
            items: Array(items)
        )
    }

    /// Ensures the live activity exists (if enabled) and has up-to-date content.
    static func syncActiveActivity(modelContext: ModelContext) async {
        guard isEnabled() else {
            await stopAllActivities()
            return
        }

        let contentState = snapshot(modelContext: modelContext)
        let attributes = LifeOSLiveActivityAttributes()
        let content = ActivityContent(state: contentState, staleDate: nil)

        let activities = Activity<LifeOSLiveActivityAttributes>.activities
        if activities.isEmpty {
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                print("Live Activities start failed: \(error)")
            }
        } else {
            for activity in activities {
                await activity.update(content)
            }
        }
    }

    static func stopAllActivities() async {
        let activities = Activity<LifeOSLiveActivityAttributes>.activities
        for activity in activities {
            let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }

    /// Convenience for intents / contexts without an injected ModelContext.
    static func syncActiveActivity() async {
        await syncActiveActivity(modelContext: LifeOSSharedStore.container.mainContext)
    }
}
