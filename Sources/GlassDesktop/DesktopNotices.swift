import Foundation
import Observation
import UserNotifications
import GlassConnectionUI

@MainActor
struct DesktopNoticeDelivery {
    var authorize: () async throws -> Bool = { try await GlassSystemNotifications.requestAuthorization() }
    var failure: (UUID) async throws -> Bool = { id in
        try await GlassSystemNotifications.post(title: "Remote Desktop Interrupted",
            body: "A remote desktop connection needs attention. Open glassDT to reconnect.",
            threadIdentifier: "app.glassdt.connection-failures", identifier: id.uuidString)
    }
}

@MainActor @Observable
public final class DesktopNotices {
    public static let shared = DesktopNotices(defaults: .standard)
    public private(set) var isEnabled: Bool
    public private(set) var isRequestingAuthorization = false
    public private(set) var statusMessage: String?
    private let defaults: UserDefaults
    private let delivery: DesktopNoticeDelivery
    private var notified: [UUID] = []
    private let delegate = DesktopNoticeDelegate()
    static let preferenceKey = "importantSessionNotificationsEnabled"

    init(defaults: UserDefaults, delivery: DesktopNoticeDelivery = .init()) {
        self.defaults = defaults; self.delivery = delivery
        isEnabled = defaults.bool(forKey: Self.preferenceKey)
    }

    public func configurePresentation() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    public func setEnabled(_ enabled: Bool) async {
        guard !isRequestingAuthorization else { return }
        statusMessage = nil
        guard enabled else { save(false); return }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        do {
            let granted = try await delivery.authorize()
            save(granted)
            if !granted { statusMessage = "Allow notifications for glassDT in system settings to receive notices." }
        } catch {
            save(false); statusMessage = "Notifications could not be enabled. Please try again."
        }
    }

    func connectionFailed(attempt: UUID) async {
        guard isEnabled, !notified.contains(attempt) else { return }
        notified.append(attempt)
        if notified.count > 128 { notified.removeFirst(notified.count - 128) }
        do {
            let delivered = try await delivery.failure(attempt)
            if !delivered {
                save(false); statusMessage = "Notifications are disabled in system settings."
            }
        } catch { statusMessage = "The connection notice could not be delivered." }
    }

    private func save(_ enabled: Bool) {
        isEnabled = enabled; defaults.set(enabled, forKey: Self.preferenceKey)
    }
}

private final class DesktopNoticeDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
