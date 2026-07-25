import Foundation
import UserNotifications

/// Ensures banners/sounds show even while LifeOS is in the foreground.
final class LifeOSNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LifeOSNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }
}
