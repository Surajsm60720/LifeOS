import ActivityKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class LiveActivityManager {
    static let enabledStorageKey = "liveActivityEnabled"
    static let defaultScopeStorageKey = "liveActivityDefaultScope"

    private static func defaultScope() -> LiveActivityScope {
        let raw = UserDefaults.standard.string(forKey: defaultScopeStorageKey) ?? LiveActivityScope.day.rawValue
        return LiveActivityScope(rawValue: raw) ?? .day
    }

    static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledStorageKey)
    }

    /// Computes the content state for the given scope using current SwiftData models.
    static func snapshot(
        for scope: LiveActivityScope,
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) -> LifeOSLiveActivityAttributes.ContentState {
        let descriptor = FetchDescriptor<Entry>()
        let entries = (try? modelContext.fetch(descriptor)) ?? []

        let now = Date()
        let interval: DateInterval
        switch scope {
        case .day:
            interval = DateInterval(start: DateFormatting.startOfDay(now, calendar: calendar), duration: 86_400)
        case .week:
            interval = DateFormatting.weekInterval(containing: now, calendar: calendar)
        case .month:
            interval = DateFormatting.monthInterval(containing: now, calendar: calendar)
        case .year:
            interval = DateFormatting.yearInterval(containing: now, calendar: calendar)
        }

        let occurrences = RecurrenceEngine.shared.expandEntries(entries, in: interval, calendar: calendar)
        let open = occurrences.filter { occ in
            occ.entry.isCompletable && !occ.entry.isCompleted(on: occ.occurrenceDate, calendar: calendar)
        }
        let sorted = open.sorted { a, b in
            if a.occurrenceDate != b.occurrenceDate {
                return a.occurrenceDate < b.occurrenceDate
            }
            return a.entry.title.localizedCaseInsensitiveCompare(b.entry.title) == .orderedAscending
        }

        let items = sorted.prefix(8).map { occ in
            let fallbackHex = "C8CCD4"
            let derivedHex = occ.entry.displayColor.hexString ?? fallbackHex
            let colorHex = occ.entry.colorOverrideHex ?? derivedHex
            return LiveActivityItem(title: occ.entry.title, colorHex: colorHex)
        }

        return LifeOSLiveActivityAttributes.ContentState(
            scope: scope,
            remainingCount: sorted.count,
            items: Array(items)
        )
    }

    /// Ensures the live activity exists (if enabled) and has up-to-date content.
    static func syncActiveActivity(modelContext: ModelContext, scopeOverride: LiveActivityScope? = nil) async {
        guard isEnabled() else {
            await stopAllActivities()
            return
        }

        let scope = scopeOverride ?? defaultScope()
        await syncActiveActivity(modelContext: modelContext, scope: scope)
    }

    static func syncActiveActivity(modelContext: ModelContext, scope: LiveActivityScope) async {
        let contentState = snapshot(for: scope, modelContext: modelContext)
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
    static func syncActiveActivity(scopeOverride: LiveActivityScope? = nil) async {
        await syncActiveActivity(
            modelContext: LifeOSSharedStore.container.mainContext,
            scopeOverride: scopeOverride
        )
    }
}
