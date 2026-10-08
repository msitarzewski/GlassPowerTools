#if os(macOS)
import AppKit
import SwiftUI
import Testing
import GlassConnectionKit
@testable import GlassConnectionUI

/// SwiftUI owns the library's split view, autosave name included (2026-10-08).
///
/// The library used to rename SwiftUI's `NSSplitView` from outside, on every update, a run-loop
/// turn after SwiftUI had set it up. Renaming it makes AppKit restore whatever layout is saved
/// under the new name, behind SwiftUI's back: a reproducer showed the sidebar collapsed while
/// SwiftUI's own visibility still said `.all`. The Workgroups window carried the same attachment
/// and crashed in a SwiftUI toolbar update while being resized; that link was not reproduced, but
/// one owner per AppKit object is the rule either way. Nothing here touches the split view.
@Suite(.serialized) @MainActor
struct LibrarySplitViewOwnerTests {
    @Test("Nothing renames the split view SwiftUI built for the library")
    func theSplitViewKeepsSwiftUIsName() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let library = GlassConnectionLibrary<String, Text, Text>(
            items: [], selection: .constant(nil), scope: .constant(.allConnections),
            searchText: .constant(""), onActivate: { _ in },
            row: { Text($0.name) }, detail: { _ in Text("Detail") })
        window.contentView = NSHostingView(rootView: library)
        window.contentView?.layoutSubtreeIfNeeded()

        let split = try #require(await splitView(in: window), "SwiftUI built no split view to check")
        let named = split.autosaveName
        // The old attachment renamed it asynchronously, so give the main queue several turns.
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(20))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        #expect(split.autosaveName == named,
                "the split view was renamed from \(named ?? "nil") to \(split.autosaveName ?? "nil") — a second owner")
        #expect(!(split.autosaveName ?? "").hasPrefix("com.glasspowertools"),
                "a Glass autosave name on SwiftUI's split view restores layouts SwiftUI never asked for")
    }

    /// SwiftUI builds the split view lazily; wait a few turns for it.
    private func splitView(in window: NSWindow) async -> NSSplitView? {
        for _ in 0..<20 {
            if let split = Self.firstSplitView(in: window.contentView) { return split }
            try? await Task.sleep(for: .milliseconds(20))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        return nil
    }

    private static func firstSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let split = view as? NSSplitView { return split }
        for subview in view.subviews {
            if let split = firstSplitView(in: subview) { return split }
        }
        return nil
    }
}
#endif
