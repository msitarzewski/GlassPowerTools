//
//  GlassRemoteChangeReceiver.swift
//  Glass Power Tools — GlassShell
//
//  The receiving half of D19's live sync. `GlassCloudKitCatalogBackend.subscribeToChanges` asks
//  CloudKit to send a silent push when the library changes on another device; this is what turns
//  that push into a sync.
//
//  It is deliberately two small functions rather than a delegate of its own. Each platform already
//  has exactly one application delegate, and taking a second one is not possible — so the app's
//  delegate calls these, and the layering stays honest: the shell never imports the terminal's.
//

import Foundation
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Registration and delivery for the silent pushes that carry "the library changed elsewhere".
public enum GlassRemoteChangeReceiver {

    /// Asks the system for a push token. Silent pushes need no user permission and show nothing,
    /// so there is no prompt and nothing to decline.
    ///
    /// Failure here is not an error worth surfacing: a device with no push token still syncs on
    /// foreground, which is the fallback the whole design assumes.
    @MainActor
    public static func register() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif canImport(AppKit)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Called by the app delegate when a silent push arrives. Posts the notification the shell
    /// model is listening for.
    ///
    /// Every CloudKit push in this container means the same thing — something in the host zone
    /// changed — so the payload is not inspected. The sync that follows fetches by change token
    /// and finds out what actually moved.
    public static func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        Logger.remoteChange.debug("Silent push received; reconciling the library")
        NotificationCenter.default.post(name: GlassShellModel.remoteChangeNotification, object: nil)
    }

    /// Registration failed — logged, never surfaced. The app is fully usable without push; it
    /// simply reconciles at foreground instead of the moment a change lands.
    public static func registrationFailed(_ error: any Error) {
        Logger.remoteChange.notice("Push registration unavailable, falling back to sync on foreground: \(error.localizedDescription, privacy: .public)")
    }
}

private extension Logger {
    static let remoteChange = Logger(subsystem: "com.glasspowertools", category: "remote-change")
}
