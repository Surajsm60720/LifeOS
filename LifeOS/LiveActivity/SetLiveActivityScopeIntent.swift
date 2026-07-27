import AppIntents
import Foundation

/// Must be a `LiveActivityIntent` so Dynamic Island / Lock Screen buttons can run it
/// without opening the app UI.
struct SetLiveActivityScopeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Switch Calendar Scope"
    static var description = IntentDescription("Updates the Live Activity list for Day, Week, Month, or Year.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Scope")
    var scope: LiveActivityScope

    init() {
        self.scope = .day
    }

    init(scope: LiveActivityScope) {
        self.scope = scope
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(scope.rawValue, forKey: LiveActivityManager.defaultScopeStorageKey)
        await LiveActivityManager.syncActiveActivity(
            modelContext: LifeOSSharedStore.container.mainContext,
            scopeOverride: scope
        )
        return .result()
    }
}
