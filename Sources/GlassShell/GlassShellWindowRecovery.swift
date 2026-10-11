//
//  GlassShellWindowRecovery.swift
//  Glass Power Tools — GlassShell
//
//  Window recovery on visionOS (moved from glas.sh's WindowRecoveryManager on 2026-09-10): when
//  the last visible window closes, decide whether to park the library as its orb, leave the space
//  empty (the quit gesture), or bring the library back. Every scene that should count as "visible"
//  attaches `trackWindowPresence(key:recovery:)`.
//
//  **The orb is the Connections window itself** (W39). It was a scene of its own ("minimized"),
//  pushed over Connections for idle and opened in its place for parking. Pushed, visionOS left
//  Connections on screen beside it on the owner's headset after a relaunch (2026-10-11: "The orb
//  always appears as it should. The All Connections window never minimizes"), so Connections now
//  becomes its own orb (`glassConnectionsIdleShrink`), and parking opens Connections as its orb
//  rather than opening a second kind of window: one orb, whichever way it came.
//

import SwiftUI
import Observation
import GlassConnectionUI
import os

@MainActor
@Observable
public final class GlassWindowRecoveryManager {
    public init() {}

    public private(set) var visibleWindowKeys: Set<String> = []
    /// The Connections windows standing as their orb now, by each window's own token (W39).
    public private(set) var orbConnectionsWindows: Set<UUID> = []
    private var recoveryTask: Task<Void, Never>?
    private var openWindowAction: OpenWindowAction?
    /// Whether the Connections window that closed last was its orb at the time.
    @ObservationIgnored private var closedConnectionsWasOrb = false
    /// The "Open Connections" count a park was asked at (`GlassConnectionsRequests`), until the
    /// window it opened takes it. Any later request for Connections is a person asking for the
    /// library, which an orb would not answer, so it makes the park stale. Not observed: it is
    /// read while SwiftUI builds the window's views.
    @ObservationIgnored private var parkedAtRequest: Int?

    public func setOpenWindowAction(_ action: OpenWindowAction) {
        openWindowAction = action
    }

    public func markWindowVisible(_ key: String) {
        visibleWindowKeys.insert(key)
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    public func markWindowHidden(_ key: String) {
        visibleWindowKeys.remove(key)
        scheduleRecoveryIfNeeded(lastClosed: key)
    }

    // MARK: Connections as its orb (W39)

    /// A Connections window became its orb.
    public func connectionsBecameOrb(_ window: UUID) { orbConnectionsWindows.insert(window) }

    /// A Connections window is the library again.
    public func connectionsBecameLibrary(_ window: UUID) { orbConnectionsWindows.remove(window) }

    /// A Connections window closed; recovery asks, a moment later, whether it was its orb.
    public func connectionsWindowClosed(_ window: UUID) {
        closedConnectionsWasOrb = orbConnectionsWindows.remove(window) != nil
    }

    /// Whether a Connections window other than `window` already stands as the orb. There is one
    /// orb: a second Connections window that goes idle beside it closes rather than become another.
    public func anotherConnectionsWindowIsOrb(than window: UUID) -> Bool {
        !orbConnectionsWindows.subtracting([window]).isEmpty
    }

    /// Whether the Connections window opening now was opened to be the orb (parked), without
    /// taking the request: read as the window's first state is chosen, before it is drawn.
    public var connectionsParkIsPending: Bool {
        #if os(visionOS)
        parkedAtRequest != nil && parkedAtRequest == GlassConnectionsRequests.shared.untrackedCount
        #else
        false
        #endif
    }

    /// Takes the park, once: true when the window appearing now was opened to be the orb.
    public func takeConnectionsPark() -> Bool {
        defer { parkedAtRequest = nil }
        return connectionsParkIsPending
    }

    // MARK: The last window

    /// What happens once the last visible window has closed.
    public enum LastWindowAction: Equatable, Sendable {
        /// Connections opens again, as its orb: the library closed last on the headset.
        case parkConnectionsAsOrb
        /// Nothing: the orb closed last, which is the quit gesture — or, off the headset, the
        /// library closed, which leaves the app with no window as the platform expects.
        case leaveEmpty
        /// Connections opens again: a terminal, Files, a preview or another session closed last.
        case openConnections
    }

    /// The rule, kept apart from the windows so it can be tested:
    /// - Connections (`main`) closed last as the library → park it as its orb (headset only).
    /// - Connections closed last as its orb             → leave the space empty (the quit gesture).
    /// - anything else closed last                      → reopen Connections.
    public nonisolated static func actionAfterLastWindow(closed key: String, connectionsWasOrb: Bool,
                                                         parksAsOrb: Bool) -> LastWindowAction {
        guard key == GlassConnectionsWindow.sceneID else { return .openConnections }
        return parksAsOrb && !connectionsWasOrb ? .parkConnectionsAsOrb : .leaveEmpty
    }

    /// When the last visible window closes, do what `actionAfterLastWindow` says. The 220 ms
    /// debounce avoids firing during window-to-window handoffs, and lets every view of the closed
    /// window report first (`connectionsWindowClosed`).
    private func scheduleRecoveryIfNeeded(lastClosed: String) {
        guard visibleWindowKeys.isEmpty else { return }
        recoveryTask?.cancel()
        recoveryTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard visibleWindowKeys.isEmpty else { return }
            #if os(visionOS)
            let parksAsOrb = true
            #else
            let parksAsOrb = false
            #endif
            switch Self.actionAfterLastWindow(closed: lastClosed, connectionsWasOrb: closedConnectionsWasOrb,
                                              parksAsOrb: parksAsOrb) {
            case .parkConnectionsAsOrb:
                guard let openWindowAction else { return }
                Logger.recovery.info("Connections closed last: opening it again as its orb")
                openWindowAction.openConnections()
                #if os(visionOS)
                // After the request, which counts itself: the park is good until the next one.
                parkedAtRequest = GlassConnectionsRequests.shared.untrackedCount
                #endif
            case .leaveEmpty:
                break
            case .openConnections:
                openWindowAction?.openConnections()
            }
        }
    }
}


private struct WindowPresenceTrackingModifier: ViewModifier {
    let key: String
    let recovery: GlassWindowRecoveryManager
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                recovery.setOpenWindowAction(openWindow)
                recovery.markWindowVisible(key)
            }
            .onDisappear {
                recovery.markWindowHidden(key)
            }
    }
}

public extension View {
    /// Counts this scene's content as a visible window for recovery purposes.
    func trackWindowPresence(key: String, recovery: GlassWindowRecoveryManager) -> some View {
        modifier(WindowPresenceTrackingModifier(key: key, recovery: recovery))
    }
}

extension Logger {
    static let recovery = Logger(subsystem: "com.glasspowertools", category: "window-recovery")
}
