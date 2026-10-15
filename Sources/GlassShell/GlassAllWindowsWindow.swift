//
//  GlassAllWindowsWindow.swift
//  Glass Power Tools — GlassShell
//
//  All Windows on Vision Pro (the owner, 2026-10-14: hold the ⚡, and "a Siri action on
//  visionOS"). No layer over the room and no immersive space — the windows are already around
//  the person — but a window of its own, with what is open as cards. Choosing one brings that
//  window to the person (`GlassOpenSession.activate`), the system's own way to find one that is
//  behind them or across the room, and this window leaves.
//
//  It was a sheet on Connections until the owner asked: "Right now it's a modal, will that work for
//  larger workloads?" A sheet is one size that can't be changed and covers the window under it; a
//  window can be made as large as the work needs, and the cards grow with it
//  (`GlassAllWindowsLayout`).
//

#if os(visionOS)
import SwiftUI

public extension GlassShowAllWindows {
    /// The headset's All Windows window: one, brought forward when asked for again.
    static let windowID = "all-windows"

    /// The headset: All Windows' window, opened or brought forward.
    static func presentOverview(openWindow: OpenWindowAction) {
        openWindow(id: windowID)
    }
}

/// All Windows as its window shows it. The composition root puts it inside every capability's
/// bootstrap, as it does Connections: what a card asks for (a terminal's window, a desktop's) is
/// carried out by a window's bootstrap, and Connections may not be open.
public struct GlassAllWindowsWindow: View {
    private let model: GlassShellModel
    @Environment(\.dismissWindow) private var dismissWindow

    public init(model: GlassShellModel) {
        self.model = model
    }

    public var body: some View {
        GlassShowAllWindowsOverview(model: model, done: leave, open: { chosen in
            chosen()
            // After what was chosen has been carried out — by this window's bootstrap when no
            // Connections window is open — so the window it asked for comes forward first.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                leave()
            }
        })
        .frame(minWidth: 640, minHeight: 440)
    }

    private func leave() {
        dismissWindow(id: GlassShowAllWindows.windowID)
    }
}
#endif
