#if os(macOS)
import Foundation
import Quartz
import Testing
@testable import GlassEditor

/// The editor's Quick Look view (0.4.406 aborted on the owner's Mac, 2026-10-13 18:47, closing one).
@Suite("Quick Look in the editor")
@MainActor
struct GlassQuickLookViewTests {
    /// Quick Look closes a view itself as it leaves its window unless told not to, and a second close
    /// — SwiftUI's dismantle — aborts the process. (Reproduced in a separate process; it cannot be run
    /// here, where it would abort the test runner.)
    @Test("the view is closed by its own teardown alone, never by Quick Look as well")
    func closedOnce() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("glass-ql-\(UUID().uuidString).txt")
        try Data("hello\n".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let view = GlassQuickLookView.makeView(file)
        #expect(view.shouldCloseWithWindow == false)
        #expect(view.autostarts == false)
        view.close()
    }
}
#endif
