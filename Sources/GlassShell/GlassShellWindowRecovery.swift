//
//  GlassShellWindowRecovery.swift
//  Glass Power Tools — GlassShell
//
//  Window recovery on visionOS (moved from glas.sh's WindowRecoveryManager on 2026-09-10): when
//  the last visible window closes, decide whether to park the library as the minimized spinner,
//  leave the space empty (the quit gesture), or bring the library back. Every scene that should
//  count as "visible" attaches `trackWindowPresence(key:recovery:)`.
//

import SwiftUI
import Observation
import os

@MainActor
@Observable
public final class GlassWindowRecoveryManager {
    public init() {}

    public private(set) var visibleWindowKeys: Set<String> = []
    private var recoveryTask: Task<Void, Never>?
    private var openWindowAction: OpenWindowAction?

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

    /// When the last visible window closes, decide what to bring back:
    /// - Connections (`main`) was the last window  → park it as the minimized spinner.
    /// - the minimized spinner was the last window → leave the space empty (this is the quit gesture).
    /// - a terminal / SFTP / preview was the last  → reopen Connections.
    /// The 220ms debounce avoids firing during window-to-window handoffs.
    private func scheduleRecoveryIfNeeded(lastClosed: String) {
        guard visibleWindowKeys.isEmpty else { return }
        recoveryTask?.cancel()
        recoveryTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard visibleWindowKeys.isEmpty else { return }
            switch lastClosed {
            case "main":
                openWindowAction?(id: "minimized")
            case "minimized":
                break
            default:
                openWindowAction?(id: "main")
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
