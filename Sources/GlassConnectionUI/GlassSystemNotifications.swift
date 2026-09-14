import Foundation
import UserNotifications

/// Native notification delivery shared by Glass apps. Apps own consent preferences,
/// event selection and privacy-safe wording; credential and protocol data stay out.
@MainActor
public enum GlassSystemNotifications {
    public static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    @discardableResult
    public static func post(title: String, body: String, threadIdentifier: String,
                            identifier: String = UUID().uuidString) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = threadIdentifier
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        return true
    }
}
