#if os(macOS)
import AppKit
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

    /// A drag comes from a window on screen: the registry knows the controller it shows.
    private func show(_ controller: MacWorkspaceWindowController) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        MacWorkspacePreviewRegistry.shared.register(controller, window: window)
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
            let shown = show(source)
            defer { MacWorkspacePreviewRegistry.shared.remove(source.windowID) }
            let moving = source.tabs[1]
            #expect(destination.acceptDroppedTab(.init(windowID: source.windowID, workspaceID: moving.workspaceID), at: 0))
            #expect(source.tabs.count == 1 && !source.closesAfterLastTabLeft)
            #expect(destination.tabs.first === moving, "the very tab, terminals and all")
            #expect(destination.selectedTabID == moving.workspaceID && !moving.isClosed)
            let reopened = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(windowID: destination.windowID, tabs: []), defaults: defaults)
            #expect(reopened.tabs.map(\.workspaceID).contains(moving.workspaceID), "saved with its new window")
            withExtendedLifetime(shown) {}
        }
    }

    @Test("a window whose last tab leaves closes, holding nothing that moved")
    func lastTab() throws {
        try withDefaults { defaults in
            let source = window(defaults, tabs: 1), destination = window(defaults, tabs: 1)
            let shown = show(source)
            defer { MacWorkspacePreviewRegistry.shared.remove(source.windowID) }
            let moving = source.tabs[0]
            #expect(destination.acceptDroppedTab(.init(windowID: source.windowID, workspaceID: moving.workspaceID), at: 1))
            #expect(source.closesAfterLastTabLeft)
            #expect(source.tabs.count == 1 && source.tabs[0] !== moving, "a placeholder stands in until it closes")
            #expect(destination.tabs.last === moving)
            source.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
            #expect(!moving.isClosed, "closing the emptied window does not stop the tab that left")
            #expect(source.detachTabForMove(source.tabs[0].workspaceID) == nil, "a closing window gives nothing more")
            withExtendedLifetime(shown) {}
        }
    }

    @Test("a full window, or a window that is gone or not on screen, takes nothing")
    func refusing() throws {
        try withDefaults { defaults in
            let source = window(defaults, tabs: 2)
            let full = window(defaults, tabs: MacWorkspaceWindowRestorationState.maximumTabCount)
            let tab = source.tabs[0].workspaceID
            #expect(!full.acceptDroppedTab(.init(windowID: source.windowID, workspaceID: tab), at: 0))
            #expect(source.tabs.count == 2, "nothing left the source")
            #expect(!full.acceptDroppedTab(.init(windowID: UUID(), workspaceID: tab), at: 0))
            let destination = window(defaults, tabs: 1)
            #expect(!destination.acceptDroppedTab(.init(windowID: source.windowID, workspaceID: tab), at: 0),
                    "a controller no window shows gives nothing")
            #expect(source.tabs.count == 2)
        }
    }

    // MARK: Several selected tabs dragged together (W8)

    @Test("a drop's tabs arrive together, in the order dragged, whatever order they load in")
    func loadingSeveral() async throws {
        let drags = (0..<3).map { _ in MacWorkspaceTabDrag(windowID: UUID(), workspaceID: UUID()) }
        let providers = drags.map { $0.itemProvider() } + [NSItemProvider(object: "not a tab" as NSString)]
        let loaded = await withCheckedContinuation { continuation in
            MacWorkspaceTabDrag.load(from: providers) { continuation.resume(returning: $0) }
        }
        #expect(loaded == drags)
    }

    @Test("several tabs dropped on another window move there together, in sidebar order, all or none")
    func movingSeveral() throws {
        try withDefaults { defaults in
            let source = window(defaults, tabs: 4), destination = window(defaults, tabs: 1)
            let shown = show(source)
            defer { MacWorkspacePreviewRegistry.shared.remove(source.windowID) }
            let t = source.tabs
            // Payloads in another order than the sidebar's.
            let drags = [t[3], t[1]].map { MacWorkspaceTabDrag(windowID: source.windowID, workspaceID: $0.workspaceID) }

            let full = window(defaults, tabs: MacWorkspaceWindowRestorationState.maximumTabCount - 1)
            #expect(!full.acceptDroppedTabs(drags, at: 0), "room for one of them is not room for both")
            #expect(source.tabs.map(\.workspaceID) == t.map(\.workspaceID), "so neither left")

            #expect(destination.acceptDroppedTabs(drags, at: 1))
            #expect(destination.tabs.count == 3 && destination.tabs[1] === t[1] && destination.tabs[2] === t[3])
            #expect(destination.selectedTabIDs == [t[1].workspaceID, t[3].workspaceID] && destination.selectedTabID == t[1].workspaceID,
                    "they arrive selected, the first shown")
            #expect(source.tabs.map(\.workspaceID) == [t[0], t[2]].map(\.workspaceID))
            let reopened = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(windowID: source.windowID, tabs: []), defaults: defaults)
            #expect(reopened.tabs.map(\.workspaceID) == [t[0], t[2]].map(\.workspaceID), "the source saved what it kept")
            withExtendedLifetime(shown) {}
        }
    }

    @Test("several tabs dragged within a window move as a block, keeping their order")
    func reorderingSeveral() throws {
        try withDefaults { defaults in
            let w = window(defaults, tabs: 5)
            let ids = w.tabs.map(\.workspaceID)
            let (a, b, c, d, e) = (ids[0], ids[1], ids[2], ids[3], ids[4])
            @MainActor func drop(_ moving: [UUID], at index: Int) -> Bool {
                w.acceptDroppedTabs(moving.map { MacWorkspaceTabDrag(windowID: w.windowID, workspaceID: $0) }, at: index)
            }
            #expect(drop([d, b], at: 0))
            #expect(w.tabs.map(\.workspaceID) == [b, d, a, c, e])
            #expect(drop([b, d], at: 5))
            #expect(w.tabs.map(\.workspaceID) == [a, c, e, b, d])
            #expect(drop([a, b], at: 3))
            #expect(w.tabs.map(\.workspaceID) == [c, e, a, b, d], "landing between e and b as they were")
        }
    }

    /// The copy the owner saw (2026-10-08): a second controller for the dragging window, made
    /// from its saved tabs, holds the same tab ids and session names but no terminals. Taking
    /// its tab left the real one attached, and with tmux the destination started a second client
    /// on the same session. No real tmux runs here: names come from the fake server, and runtimes
    /// are made without starting.
    @Test("a drop takes the tab the dragging window shows, never its twin's: same tab, same terminal, same session")
    func droppingFromAWindowWithATwin() throws {
        try withDefaults { defaults in
            let fake = MacLocalTmuxTests.FakeServer()
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let sessionManager = SessionManager(loadImmediately: false)

            // Made first and shown by no window: the twin. The real window restores the same tabs.
            let twin = window(defaults, tabs: 2)
            let real = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: twin.windowID, tabs: []), defaults: defaults)
            let destination = window(defaults, tabs: 1)
            defer {
                for controller in [destination, real, twin] { controller.closeAllSessions(sessionManager: sessionManager) }
            }
            let shown = show(real)
            defer { MacWorkspacePreviewRegistry.shared.remove(real.windowID) }
            #expect(MacWorkspacePreviewRegistry.shared.controllers(windowID: real.windowID).count == 2)

            let tab = real.tabs[1]
            let pane = try #require(tab.focusedPaneID)
            let name = try #require(tab.localTmuxSession(for: pane))
            #expect(twin.tabs[1].workspaceID == tab.workspaceID && twin.tabs[1].localTmuxSession(for: pane) == name,
                    "the twin holds the same tab and session")
            let runtime = try #require(tab.localRuntime(for: pane), "the real window's terminal")
            let shownBefore = MacLocalTmux.shownHere[name, default: 0]
            #expect(shownBefore == 1)

            #expect(destination.acceptDroppedTab(.init(windowID: real.windowID, workspaceID: tab.workspaceID),
                                                 at: destination.tabs.count))
            #expect(!real.tabs.contains { $0.workspaceID == tab.workspaceID }, "gone from the window it left")
            #expect(destination.tabs.last === tab, "the very tab")
            #expect(destination.tabs.last?.localRuntime(for: pane) === runtime, "its terminal, not a new one")
            #expect(destination.tabs.last?.localTmuxSession(for: pane) == name, "its session")
            #expect(MacLocalTmux.shownHere[name, default: 0] == shownBefore, "no second client")
            #expect(twin.tabs.contains { $0.workspaceID == tab.workspaceID }, "the twin was not touched")
            withExtendedLifetime(shown) {}
        }
    }
}
#endif
