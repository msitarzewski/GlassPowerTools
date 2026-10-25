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
        #if os(iOS)
        // A UI test starts as on a fresh install. iPadOS brings back every window an earlier
        // launch left open, so a database window one test opened, its session long gone, stood in
        // front of the next test's library (18 failures in the 2026-10-24 iPad run). Only a UI-test
        // launch (`--ui-testing`, Debug); a person's windows come back as iPadOS brings them.
        // Discarding them leaves no window at all, so one fresh default window (the library) is
        // asked for once launch is done.
        if GlassUITestRun.identifier != nil, application.openSessions.count > 1 {
            for session in application.openSessions {
                application.requestSceneSessionDestruction(session, options: nil)
            }
            DispatchQueue.main.async {
                UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil)
            }
        }
        #endif
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
