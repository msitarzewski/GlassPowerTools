//
//  GlassAllWindowsSheet.swift
//  Glass Power Tools — GlassShell
//
//  All Windows on Vision Pro (the owner, 2026-10-14: hold the ⚡, and "a Siri action on
//  visionOS"). No layer over the room and no immersive space — the windows are already around
//  the person — but the Connections window, brought forward, with what is open as cards on a
//  sheet. Choosing one brings that window to the person (`GlassOpenSession.activate`), the
//  system's own way to find one that is behind them or across the room.
//

#if os(visionOS)
import SwiftUI
import GlassConnectionUI

/// Whether the headset's Connections window is showing All Windows.
@MainActor @Observable
final class GlassAllWindowsRequest {
    static let shared = GlassAllWindowsRequest()
    var isShowing = false
}

public extension GlassShowAllWindows {
    /// The headset: Connections brought forward, All Windows on it.
    static func presentOverview(openWindow: OpenWindowAction) {
        openWindow.openConnections()
        GlassAllWindowsRequest.shared.isShowing = true
    }
}

/// All Windows as a sheet on the Connections window.
struct GlassAllWindowsSheet: ViewModifier {
    let model: GlassShellModel

    func body(content: Content) -> some View {
        let request = GlassAllWindowsRequest.shared
        content.sheet(isPresented: Binding(get: { request.isShowing }, set: { request.isShowing = $0 })) {
            GlassShowAllWindowsOverview(model: model, done: { request.isShowing = false }, open: { chosen in
                request.isShowing = false
                chosen()
            })
            .frame(minWidth: 760, minHeight: 560)
        }
    }
}
#endif
