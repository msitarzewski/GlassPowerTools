//
//  GlassHandoff.swift
//  Glass Power Tools — GlassShell
//
//  Handoff (D72, 2026-10-13): the terminal, database or desktop in front is offered on your other
//  devices — "Continue" in the Mac's Dock, the iPhone's app switcher — and picking it up there
//  connects the same service the way the library's Connect does, sign-in and host trust included.
//  The activity names the service by its endpoint, which every device's library knows from the
//  synced catalog (D26); nothing else is in it — no address, no user, no credential.
//

import Foundation
import SwiftUI

public enum GlassHandoff {
    public static let activityType = "com.glasspowertools.session"

    /// The service a continued activity names.
    public static func endpoint(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == activityType else { return nil }
        return (activity.userInfo?["endpoint"] as? String).flatMap(UUID.init(uuidString:))
    }

    static func describe(_ activity: NSUserActivity, endpoint: UUID, title: String) {
        activity.title = title
        activity.userInfo = ["endpoint": endpoint.uuidString]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        #if !os(macOS)
        activity.isEligibleForPrediction = false
        #endif
    }
}

public extension View {
    /// Offers the service this window shows to your other devices while the window is in front.
    /// Nothing is offered for `endpoint` nil — a local terminal, which another device cannot open.
    func glassHandoff(endpoint: UUID?, title: String) -> some View {
        userActivity(GlassHandoff.activityType, isActive: endpoint != nil) { activity in
            guard let endpoint else { return }
            GlassHandoff.describe(activity, endpoint: endpoint, title: title)
        }
    }
}
