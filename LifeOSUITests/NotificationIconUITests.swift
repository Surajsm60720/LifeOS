import XCTest

/// Reproduces the "notification banner icon" issue end-to-end:
/// grants permission, fires the in-app test notification, and captures
/// a screenshot of the banner so the glyph can be inspected.
final class NotificationIconUITests: XCTestCase {

    @MainActor
    func testNotificationBannerShowsAppIcon() throws {
        let app = XCUIApplication()
        app.launch()

        // Accept the notification permission alert (rendered by SpringBoard).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 8) {
            allowButton.tap()
        }

        // Navigate to the Notifications tab and schedule the 5s test.
        let notificationsTab = app.tabBars.buttons["Notifications"]
        XCTAssertTrue(notificationsTab.waitForExistence(timeout: 8), "Notifications tab not found")
        notificationsTab.tap()

        let sendButton = app.buttons["Send Test in 5s"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 8), "Send Test button not found")
        sendButton.tap()

        // Banner appears ~5s later (foreground presentation is enabled via delegate).
        sleep(9)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "notification-banner"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Best-effort copy for direct inspection outside the xcresult bundle.
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/lifeos_banner.png"))
    }
}
