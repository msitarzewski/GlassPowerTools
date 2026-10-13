//
//  GlassShowAllWindows.swift
//  Glass Power Tools — GlassShell
//
//  **Show All Windows**: the Mac's overview of every window the app has open, and the one control
//  that opens it, in every kind of window. It began as Show All Terminals (W9), the terminal's own;
//  the owner, 2026-10-13, after trying it from a desktop: "I'd also like our 'expose' feature to
//  include all of our connection/service types", then "Seems then that the expose tools should be
//  available in every window type now then? one component?"
//
//  So, like the ⚡ (`GlassActiveConnections.swift`): the shell owns the action and the button, the
//  terminal draws the overlay — terminal windows with a tile per tab, as before — and every other
//  open session joins it from the shell's list (`GlassCapabilityRegistry.openSessions`), a group
//  per kind. ⇧⌘\ and Window ▸ Show All Windows keep their one owner (`TerminalLibraryCommands`).
//

import SwiftUI

@MainActor
public enum GlassShowAllWindows {
    public static let title = "Show All Windows"
    public static let symbolName = "rectangle.3.group"

    /// Opens or closes the overview. Set by the capability that draws it — the terminal, on the
    /// Mac; nil elsewhere, and then the button is not drawn rather than drawn dead.
    public static var toggle: (@MainActor (OpenWindowAction) -> Void)?

    /// Every open session, for the overview's groups beside the terminal windows. Set by the
    /// composition root, the one place that holds every capability.
    public static var openSessions: (@MainActor () -> [GlassOpenSession])?

    /// The kind a session belongs to, from its id's prefix (`GlassOpenSession.id`: "desktop:…").
    public static func kind(of session: GlassOpenSession) -> String? {
        session.id.split(separator: ":", maxSplits: 1).first.map(String.init)
    }
}

/// The toolbar's Show All Windows, the same in every window: a terminal's, a desktop's, a
/// database's, an editor's, and Connections.
public struct GlassShowAllWindowsButton: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        if let toggle = GlassShowAllWindows.toggle {
            Button(GlassShowAllWindows.title, systemImage: GlassShowAllWindows.symbolName) {
                toggle(openWindow)
            }
            .help(GlassShowAllWindows.title)
            .accessibilityIdentifier("show-all-windows")
        }
    }
}
