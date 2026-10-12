#if os(macOS)
import AppKit
import Foundation
import GlassTerminalEmulator
import Testing
@testable import GlassTerminal

/// W8 (owner, 2026-10-08): "command click multiple tabs in a window sidebar and allow 'move to new
/// window' with a right click". The owner had just moved fourteen tabs between windows one at a
/// time. Several tabs are selected, moved to one new window, or closed, together.
///
/// No real tmux runs: names come from `MacLocalTmuxTests.FakeServer`, terminals are made without
/// starting, and no test suspends while the fake is in place.
extension LocalTmuxServerSuites {
@MainActor
@Suite("Selecting several terminal tabs", .serialized)
struct MacWorkspaceTabSelectionTests {
    private let prefix = UserDefaultsKeys.macWorkspaceRestoration

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "MacWorkspaceTabSelectionTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    /// Local terminals in tmux, on a fake server.
    private func withTmux(_ body: (MacLocalTmuxTests.FakeServer, UserDefaults) throws -> Void) throws {
        try withDefaults { defaults in
            let fake = MacLocalTmuxTests.FakeServer()
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            try body(fake, defaults)
        }
    }

    /// A window of local tabs as one on screen has it: saved as it opened, each tab's terminal made.
    private func window(_ defaults: UserDefaults, tabs: Int,
                        broker: MacWorkspaceTransferBroker = MacWorkspaceTransferBroker()) -> MacWorkspaceWindowController {
        let window = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(windowID: UUID(), tabs: (0..<tabs).map { _ in
                MacWorkspaceTabRequest(initialPaneIntent: .local)
            }),
            transferBroker: broker, defaults: defaults)
        window.windowDidOpen()
        for tab in window.tabs {
            for pane in tab.state.root?.panes ?? [] { _ = tab.localRuntime(for: pane.id) }
        }
        return window
    }

    private func pane(_ tab: MacWorkspaceController) throws -> UUID {
        try #require(tab.state.root?.panes.first?.id)
    }

    private func savedWindow(_ defaults: UserDefaults, _ id: UUID) -> MacWorkspaceWindowRestorationState? {
        defaults.data(forKey: "\(prefix).window.\(id.uuidString.lowercased())")
            .flatMap { try? JSONDecoder().decode(MacWorkspaceWindowRestorationState.self, from: $0) }
    }

    private func tabRecordExists(_ defaults: UserDefaults, _ id: UUID) -> Bool {
        defaults.data(forKey: "\(prefix).\(id.uuidString.lowercased())") != nil
    }

    /// The selection the sidebar shows always holds the tab shown, and that tab is in the window.
    private func isConsistent(_ window: MacWorkspaceWindowController) -> Bool {
        window.selectedTabIDs.contains(window.selectedTabID)
            && window.selectedTabIDs.allSatisfy { id in window.tabs.contains { $0.workspaceID == id } }
            && window.tabs.contains { $0.workspaceID == window.selectedTabID }
    }

    // MARK: Moving several tabs to a new window

    @Test("Move N Tabs: one new window with exactly those tabs, in sidebar order, the same terminals and sessions")
    func movingSeveral() throws {
        try withTmux { fake, defaults in
            let broker = MacWorkspaceTransferBroker()
            let source = window(defaults, tabs: 4, broker: broker)
            var destination: MacWorkspaceWindowController?
            defer {
                let sessionManager = SessionManager(loadImmediately: false)
                for window in [source, destination].compactMap({ $0 }) { window.closeAllSessions(sessionManager: sessionManager) }
            }
            let t = source.tabs
            // Click the fourth, then ⌘-click the second: picked against sidebar order.
            source.updateSelection([t[3].workspaceID])
            source.updateSelection([t[3].workspaceID, t[1].workspaceID])
            #expect(source.selectedTabID == t[1].workspaceID, "the tab clicked last is shown")

            let moving = [t[1], t[3]]
            let panes = try moving.map(pane)
            let names = try zip(moving, panes).map { try #require($0.localTmuxSession(for: $1)) }
            let runtimes = try zip(moving, panes).map { try #require($0.localRuntime(for: $1)) }
            let shownBefore = names.map { MacLocalTmux.shownHere[$0, default: 0] }
            #expect(shownBefore == [1, 1])

            #expect(source.canTransferSelectedTab)
            let request = try #require(source.transferSelectedTab())
            #expect(source.tabs.count == 4, "nothing leaves until the new window claims them")
            let moved = MacWorkspaceWindowController(request: request, transferBroker: broker, defaults: defaults)
            destination = moved

            #expect(moved.tabs.map(\.workspaceID) == moving.map(\.workspaceID), "sidebar order, not the order clicked")
            #expect(moved.tabs.count == 2 && moved.tabs[0] === t[1] && moved.tabs[1] === t[3], "the very tabs")
            #expect(moved.selectedTabID == t[1].workspaceID, "showing the tab that was shown")
            #expect(source.tabs.map(\.workspaceID) == [t[0], t[2]].map(\.workspaceID), "the source keeps the rest")
            #expect(!source.closesAfterLastTabLeft)
            #expect(isConsistent(source) && isConsistent(moved))
            for (index, tab) in moving.enumerated() {
                #expect(!tab.isClosed)
                #expect(tab.localRuntime(for: panes[index]) === runtimes[index], "its terminal, not a new one")
                #expect(tab.localTmuxSession(for: panes[index]) == names[index], "its session")
            }
            #expect(names.map { MacLocalTmux.shownHere[$0, default: 0] } == shownBefore, "no second client")
            #expect(fake.killed.isEmpty)
            #expect(broker.pendingCount == 0)
        }
    }

    @Test("moving every tab closes the window they leave; its only tab alone stays")
    func movingEveryTab() throws {
        try withTmux { fake, defaults in
            let broker = MacWorkspaceTransferBroker()
            let source = window(defaults, tabs: 3, broker: broker)
            let sessionManager = SessionManager(loadImmediately: false)
            var destination: MacWorkspaceWindowController?
            defer { for window in [source, destination].compactMap({ $0 }) { window.closeAllSessions(sessionManager: sessionManager) } }
            let t = source.tabs
            // Click the first, ⇧-click the last: the range is every tab.
            source.updateSelection([t[0].workspaceID])
            source.updateSelection(Set(t.map(\.workspaceID)))
            #expect(source.selectedTabID == t[2].workspaceID, "the end of the range clicked is shown")
            #expect(source.selectedTabIDs.count == 3)

            let request = try #require(source.transferSelectedTab())
            let moved = MacWorkspaceWindowController(request: request, transferBroker: broker, defaults: defaults)
            destination = moved
            #expect(moved.tabs.map(\.workspaceID) == t.map(\.workspaceID))
            #expect(source.closesAfterLastTabLeft, "the window they left closes")
            #expect(source.tabs.count == 1 && !t.contains { $0 === source.tabs[0] }, "a placeholder stands in until it closes")
            #expect(savedWindow(defaults, source.windowID) == nil, "and its record goes with it")
            source.closeAllSessions(sessionManager: sessionManager)
            #expect(t.allSatisfy { !$0.isClosed }, "closing it leaves the tabs that left running")
            #expect(fake.killed.isEmpty)

            let single = window(defaults, tabs: 1)
            defer { single.closeAllSessions(sessionManager: sessionManager) }
            #expect(!single.canTransferSelectedTab && single.transferSelectedTab() == nil,
                    "a window's only tab has nowhere better to be")
        }
    }

    @Test("after the move both windows' saved records are right: a relaunch restores each, sessions and all")
    func relaunchAfterMoving() throws {
        try withTmux { _, defaults in
            let broker = MacWorkspaceTransferBroker()
            let source = window(defaults, tabs: 4, broker: broker)
            let sessionManager = SessionManager(loadImmediately: false)
            var others: [MacWorkspaceWindowController] = []
            defer { for window in [source] + others { window.closeAllSessions(sessionManager: sessionManager) } }
            let t = source.tabs
            source.updateSelection([t[2].workspaceID])
            source.updateSelection([t[2].workspaceID, t[0].workspaceID])
            let request = try #require(source.transferSelectedTab())
            let moved = MacWorkspaceWindowController(request: request, transferBroker: broker, defaults: defaults)
            others.append(moved)

            // Saved the moment the new window claimed them, before it is on screen (W7b).
            #expect(savedWindow(defaults, request.windowID)?.tabs.map(\.id) == [t[0], t[2]].map(\.workspaceID))
            #expect(savedWindow(defaults, request.windowID)?.selectedTabID == t[0].workspaceID)
            #expect(savedWindow(defaults, source.windowID)?.tabs.map(\.id) == [t[1], t[3]].map(\.workspaceID),
                    "the window they left saved the tabs it kept")

            // A crash: macOS hands each window its request again, and the ticket died with the process.
            let fresh = MacWorkspaceTransferBroker()
            let relaunchedSource = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: source.windowID, tabs: []), transferBroker: fresh, defaults: defaults)
            let relaunchedMoved = MacWorkspaceWindowController(request: request, transferBroker: fresh, defaults: defaults)
            others += [relaunchedSource, relaunchedMoved]
            #expect(relaunchedSource.tabs.map(\.workspaceID) == [t[1], t[3]].map(\.workspaceID))
            #expect(relaunchedMoved.tabs.map(\.workspaceID) == [t[0], t[2]].map(\.workspaceID))
            #expect(relaunchedMoved.selectedTabID == t[0].workspaceID)
            for (before, after) in zip([t[1], t[3], t[0], t[2]], relaunchedSource.tabs + relaunchedMoved.tabs) {
                let paneID = try pane(before)
                #expect(after.state == before.state, "the same layout")
                #expect(after.localTmuxSession(for: paneID) != nil
                        && after.localTmuxSession(for: paneID) == before.localTmuxSession(for: paneID),
                        "the same session to reattach")
            }
        }
    }

    // MARK: The tab shown

    @Test("the tab shown is the one picked last, is always selected, and never goes blank")
    func shownTab() throws {
        try withDefaults { defaults in
            let w = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: UUID(), tabs: (0..<5).map { _ in MacWorkspaceTabRequest(startsEmpty: true) }),
                defaults: defaults)
            w.windowDidOpen()
            let id = w.tabs.map(\.workspaceID)
            let (a, b, c, d, e) = (id[0], id[1], id[2], id[3], id[4])
            #expect(w.selectedTabIDs == [a] && isConsistent(w))

            w.updateSelection([b])                              // a click
            #expect(w.selectedTabID == b && w.selectedTabIDs == [b])
            w.updateSelection([b, d])                           // ⌘-click
            #expect(w.selectedTabID == d && isConsistent(w))
            w.updateSelection([a, b, c, d])                     // ⇧-click from d back to a
            #expect(w.selectedTabID == a && isConsistent(w), "the end of the range clicked")
            w.updateSelection([b, c, d])                        // ⌘-click a off
            #expect(w.selectedTabID == c && isConsistent(w), "the tab picked before it")
            w.updateSelection([])                               // a click on empty space
            #expect(w.selectedTabID == c && w.selectedTabIDs == [c], "the detail never goes blank")
            w.updateSelection([UUID()])                         // nothing this window has
            #expect(w.selectedTabID == c && w.selectedTabIDs == [c])
            w.updateSelection([c, e])
            w.updateSelection([c])                              // a plain click inside the selection
            #expect(w.selectedTabID == c && w.selectedTabIDs == [c])
            #expect(savedWindow(defaults, w.windowID)?.selectedTabID == c, "the tab shown is what a relaunch shows")

            w.updateSelection([b])
            w.updateSelection([b, d])
            let sessionManager = SessionManager(loadImmediately: false)
            #expect(!w.removeTab(d, sessionManager: sessionManager))  // ⌘W on the tab shown
            #expect(w.selectedTabID == b && w.selectedTabIDs == [b], "the other selected tab, not a stranger")
            w.updateSelection([a, e])
            w.select(c)                                         // ⌘3, the overview, Active
            #expect(w.selectedTabIDs == [c])
            w.closeAllSessions(sessionManager: sessionManager)
        }
    }

    // MARK: Closing several tabs

    @Test("Close N Tabs: in tmux nothing asks and every session detaches; closing all closes the window")
    func closingSeveralInTmux() throws {
        try withTmux { fake, defaults in
            let w = window(defaults, tabs: 4)
            let sessionManager = SessionManager(loadImmediately: false)
            defer { w.closeAllSessions(sessionManager: sessionManager) }
            let t = w.tabs
            let names = try t.map { try #require($0.localTmuxSession(for: try pane($0))) }
            let closing: Set<UUID> = [t[0].workspaceID, t[2].workspaceID]
            #expect(w.closeWarning(forTabs: closing) == nil, "terminals in tmux keep running, so nothing asks")

            #expect(!w.removeTabs(closing, sessionManager: sessionManager))
            #expect(t[0].isClosed && t[2].isClosed && !t[1].isClosed && !t[3].isClosed)
            #expect(w.tabs.map(\.workspaceID) == [t[1], t[3]].map(\.workspaceID) && isConsistent(w))
            #expect(!tabRecordExists(defaults, t[0].workspaceID) && !tabRecordExists(defaults, t[2].workspaceID),
                    "each closed tab's layout goes, as closing one does")
            #expect(savedWindow(defaults, w.windowID)?.tabs.map(\.id) == [t[1], t[3]].map(\.workspaceID))
            #expect(fake.killed.isEmpty, "closing detaches; the sessions keep running")
            #expect(MacLocalTmux.shownHere[names[0], default: 0] == 0 && MacLocalTmux.shownHere[names[2], default: 0] == 0)

            #expect(w.removeTabs(Set(w.tabs.map(\.workspaceID)), sessionManager: sessionManager), "every tab: the window closes")
            #expect(savedWindow(defaults, w.windowID) == nil)
            #expect(fake.killed.isEmpty)
        }
    }

    @Test("Close N Tabs asks when any one of them would, by the rules for closing it alone")
    func closingSeveralAsks() async throws {
        let suite = "MacWorkspaceTabSelectionTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Plain local shells, not tmux: a running command in one would stop.
        let w = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(windowID: UUID(), tabs: (0..<3).map { _ in
                MacWorkspaceTabRequest(initialPaneIntent: .local)
            }), defaults: defaults)
        let sessionManager = SessionManager(loadImmediately: false)
        defer { w.closeAllSessions(sessionManager: sessionManager) }
        let t = w.tabs
        let busyPane = try pane(t[1])
        let runtime = try #require(t[1].localRuntime(for: busyPane))
        runtime.start(
            configuration: SwiftTermLocalProcessConfiguration(
                executable: "/bin/sh", arguments: ["-i"], executableName: "sh",
                currentDirectory: FileManager.default.temporaryDirectory.path),
            theme: SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 0), cursor: (1, 1, 1)),
            runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100))
        #expect(await waitFor { runtime.hasActiveChildProcesses == false })
        #expect(runtime.processState.sendCommand("sleep 30 &"))
        #expect(await waitFor { runtime.hasActiveChildProcesses == true })
        let busy = try #require(t[1].closeWarning)
        #expect(w.selectedTabID == t[0].workspaceID, "the busy tab is not the one shown")

        let one = w.closeWarning(forTabs: [t[1].workspaceID])
        #expect(one == busy, "one tab asks exactly as closing it alone does")
        let several = try #require(w.closeWarning(forTabs: [t[0].workspaceID, t[1].workspaceID, t[2].workspaceID]),
                                   "a selection holding it asks, whichever tab is shown")
        #expect(several.hasPrefix("One of these tabs ") && several.hasSuffix(String(busy.dropFirst("This tab ".count))))
        #expect(w.closeWarning(forTabs: [t[0].workspaceID, t[2].workspaceID]) == nil, "quiet tabs close without asking")

        #expect(MacWorkspaceWindowController.closeWarning(combining: [nil, nil]) == nil)
        #expect(MacWorkspaceWindowController.closeWarning(combining: ["This tab is recording.", "This tab has running commands."])?
            .hasPrefix("2 of these tabs ") == true)

        #expect(runtime.processState.sendCommand("kill -KILL %1; wait"))
        #expect(await waitFor { runtime.hasActiveChildProcesses == false })
    }

    private func waitFor(seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
}
#endif
