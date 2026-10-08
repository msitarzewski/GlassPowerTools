#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// Terminal tabs dragged between windows (2026-10-08): a tab moves with its terminals running, a
/// window whose last tab leaves closes, and the same drag within a window reorders.
@MainActor
@Suite("Dragging terminal tabs between windows")
struct MacWorkspaceTabDragTests {
    private func window(_ defaults: UserDefaults, tabs: Int) -> MacWorkspaceWindowController {
        let window = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(), defaults: defaults)
        for _ in 1..<tabs { window.addTab() }
        return window
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "MacWorkspaceTabDragTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test("within a window the drag reorders, landing where it was dropped")
    func reordering() throws {
        try withDefaults { defaults in
            let w = window(defaults, tabs: 3)
            let ids = w.tabs.map(\.workspaceID)
            #expect(w.acceptDroppedTab(.init(windowID: w.windowID, workspaceID: ids[0]), at: 3))
            #expect(w.tabs.map(\.workspaceID) == [ids[1], ids[2], ids[0]])
            #expect(w.acceptDroppedTab(.init(windowID: w.windowID, workspaceID: ids[0]), at: 0))
            #expect(w.tabs.map(\.workspaceID) == ids)
            #expect(w.acceptDroppedTab(.init(windowID: w.windowID, workspaceID: ids[2]), at: 1))
            #expect(w.tabs.map(\.workspaceID) == [ids[0], ids[2], ids[1]])
        }
    }

    @Test("to another window, the same tab moves, is shown there, and is saved with it")
    func moving() throws {
        try withDefaults { defaults in
            let source = window(defaults, tabs: 2), destination = window(defaults, tabs: 1)
            let moving = source.tabs[1]
            #expect(destination.acceptDroppedTab(.init(windowID: source.windowID, workspaceID: moving.workspaceID), at: 0))
            #expect(source.tabs.count == 1 && !source.closesAfterLastTabLeft)
            #expect(destination.tabs.first === moving, "the very tab, terminals and all")
            #expect(destination.selectedTabID == moving.workspaceID && !moving.isClosed)
            let reopened = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(windowID: destination.windowID, tabs: []), defaults: defaults)
            #expect(reopened.tabs.map(\.workspaceID).contains(moving.workspaceID), "saved with its new window")
        }
    }

    @Test("a window whose last tab leaves closes, holding nothing that moved")
    func lastTab() throws {
        try withDefaults { defaults in
            let source = window(defaults, tabs: 1), destination = window(defaults, tabs: 1)
            let moving = source.tabs[0]
            #expect(destination.acceptDroppedTab(.init(windowID: source.windowID, workspaceID: moving.workspaceID), at: 1))
            #expect(source.closesAfterLastTabLeft)
            #expect(source.tabs.count == 1 && source.tabs[0] !== moving, "a placeholder stands in until it closes")
            #expect(destination.tabs.last === moving)
            source.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
            #expect(!moving.isClosed, "closing the emptied window does not stop the tab that left")
            #expect(source.detachTabForMove(source.tabs[0].workspaceID) == nil, "a closing window gives nothing more")
        }
    }

    @Test("a full window, or a window that is gone, takes nothing")
    func refusing() throws {
        try withDefaults { defaults in
            let source = window(defaults, tabs: 2)
            let full = window(defaults, tabs: MacWorkspaceWindowRestorationState.maximumTabCount)
            let tab = source.tabs[0].workspaceID
            #expect(!full.acceptDroppedTab(.init(windowID: source.windowID, workspaceID: tab), at: 0))
            #expect(source.tabs.count == 2, "nothing left the source")
            #expect(!full.acceptDroppedTab(.init(windowID: UUID(), workspaceID: tab), at: 0))
        }
    }
}
#endif
