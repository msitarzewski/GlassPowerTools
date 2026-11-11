import Foundation
import UserNotifications

/// Native notification delivery shared by Glass apps. Apps own consent preferences,
/// event selection and privacy-safe wording; credential and protocol data stay out.
@MainActor
public enum GlassSystemNotifications {
    public static func requestAuthorization() async throws -> Bool {
        try await requestAuthorization(options: [.alert, .sound])
    }

    /// Asks once, with these options; macOS and iOS show their prompt only while the app hasn't been answered, and
    /// after that report what the person chose (in System Settings ▸ Notifications).
    public static func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    @discardableResult
    public static func post(title: String, body: String, threadIdentifier: String,
                            identifier: String = UUID().uuidString,
                            userInfo: [String: String] = [:], playsSound: Bool = true) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playsSound { content.sound = .default }
        content.threadIdentifier = threadIdentifier
        content.userInfo = userInfo
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        return true
    }

    /// Takes back notifications still in Notification Center, by identifier: what they said is no longer so.
    public static func remove(identifiers: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// What clicking a notification does, by its thread: each feature that posts sets its own (2026-11-10: a
    /// terminal's bell, which brings that terminal forward). A thread with none just brings the app forward.
    public static var openHandlers: [String: @MainActor ([String: String]) -> Void] = [:]

    /// The app's one notification delegate: banners show while the app is in front, and a click goes to its
    /// thread's handler. Installed once, at launch.
    public static func installDelegate() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    private static let delegate = Delegate()

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            let content = response.notification.request.content
            let thread = content.threadIdentifier
            var info: [String: String] = [:]
            for (key, value) in content.userInfo {
                if let key = key as? String, let value = value as? String { info[key] = value }
            }
            await MainActor.run { GlassSystemNotifications.openHandlers[thread]?(info) }
        }
    }
}
