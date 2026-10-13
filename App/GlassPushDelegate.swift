//
//  GlassPushDelegate.swift
//  Glass Power Tools
//
//  The receiving half of D19's live sync on iOS and visionOS. macOS has the equivalent three
//  methods on `MacTerminalAppDelegate`, which already owns that platform's one delegate slot.
//
//  Nothing here decides anything: it hands every silent push to `GlassRemoteChangeReceiver`, which
//  posts the notification the shell model reconciles on.
//

#if !os(macOS)
import UIKit
import GlassLayers
import GlassShell

final class GlassPushDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in GlassRemoteChangeReceiver.register() }
        // Settings ▸ Appearance's Light, Dark or System, for every window as it appears.
        MainActor.assumeIsolated { GlassAppAppearance.install() }
        return true
    }

    /// `.newData` unconditionally: the push means the library changed somewhere, the sync it
    /// triggers is what finds out what, and claiming `.noData` would teach the system to deliver
    /// these less often.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        GlassRemoteChangeReceiver.handleRemoteNotification(userInfo)
        return .newData
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        GlassRemoteChangeReceiver.registrationFailed(error)
    }
}
#endif
