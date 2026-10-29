import BackgroundTasks
import Foundation

/// Glue for `BGTaskScheduler`. Background refresh is a bonus, not the mechanism the
/// schedule depends on — iOS may skip it entirely, so the same due-check also runs on
/// launch, foreground, and background transitions.
enum AutoBackupScheduler {
    static let identifier = "com.surajmenon.lifeos.autobackup"

    private static var didRegister = false

    /// Must be called before the app finishes launching.
    static func register() {
        guard !didRegister else { return }
        didRegister = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    static func scheduleNext() {
        guard BackupDestination.isConfigured,
              AutomaticBackup.isEnabled || AutomaticBackup.isMonthlyEnabled || AutomaticBackup.isYearlyEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }

        let now = Date()
        let due = AutomaticBackup.nextWakeDate(now: now) ?? now.addingTimeInterval(6 * 3_600)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = max(now.addingTimeInterval(15 * 60), due)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator and devices that have never granted background refresh both
            // land here. The foreground triggers still cover the schedule.
            print("Auto backup background request failed: \(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Queue the next wake-up before doing any work so a long run can't drop the chain.
        scheduleNext()

        let work = Task { @MainActor in
            let outcome = AutomaticBackup.runAllIfDue(modelContext: LifeOSSharedStore.container.mainContext)
            task.setTaskCompleted(success: outcome.succeeded)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }
}
