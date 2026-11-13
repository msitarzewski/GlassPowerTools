#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import GlassDatabase

/// B-X20: a database window opened with no workspace (the Mac's tab bar "+") showed a bare
/// `ContentUnavailableView`, whose size is its text's, so the window could be made a sliver of
/// itself. Its message now keeps a database window's size.
@Suite @MainActor
struct DatabaseWorkspaceNotFoundTests {
    @Test("the not-found window's message, offered almost no room, still takes a database window's floor")
    func keepsAWindowsSize() {
        _ = NSApplication.shared
        let host = NSHostingController(rootView: DatabaseWorkspaceNotFoundView())
        let squeezed = host.sizeThatFits(in: CGSize(width: 10, height: 10))
        #expect(squeezed.width >= DatabaseWorkspaceNotFoundView.minimumSize.width, "\(squeezed)")
        #expect(squeezed.height >= DatabaseWorkspaceNotFoundView.minimumSize.height, "\(squeezed)")
    }
}
#endif
