import SwiftUI
import SwiftData
import UserNotifications

@main
struct LifeOSApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = LifeOSNotificationDelegate.shared
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Entry.self,
            RecurrenceRule.self,
            NotificationRule.self,
            EntryProgress.self,
            EntryCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}

enum PreviewData {
    @MainActor
    static var container: ModelContainer = {
        let schema = Schema([
            Entry.self,
            RecurrenceRule.self,
            NotificationRule.self,
            EntryProgress.self,
            EntryCompletion.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(into: container.mainContext)
        return container
    }()

    @MainActor
    static func seed(into context: ModelContext) {
        let irl = Entry(title: "Dentist", category: .irl, startDate: .now, isCompletable: true)
        context.insert(irl)

        let daily = Entry(title: "Genshin Dailies", category: .game, subCategory: GameSubCategory.genshinImpact.rawValue, isCompletable: true)
        daily.recurrence = RecurrenceRule(frequency: .daily)
        daily.recurrence?.entry = daily
        let rule = NotificationRule(
            triggerKind: .ifNotCompletedBy,
            triggerDate: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now),
            messageTemplate: "Dailies still open: {title}"
        )
        rule.entry = daily
        daily.notificationRules = [rule]
        context.insert(daily)

        let anime = Entry(title: "Sample Anime", category: .entertainment, subCategory: EntertainmentSubCategory.anime.rawValue)
        anime.progress = EntryProgress(currentUnit: 3, totalUnits: 12, unitLabel: "episode")
        anime.progress?.entry = anime
        context.insert(anime)
    }
}
