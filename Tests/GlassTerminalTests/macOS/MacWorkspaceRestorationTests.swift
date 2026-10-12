#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GlassTerminal

/// W7b, 2026-10-08: after four crashes and an update, every terminal window opened as an empty
/// "New Terminal" tab while its fourteen tmux sessions kept running. The saved tab records were
/// `{"id", "schemaVersion": 1}` with no layout, and the one window record listed a single empty
/// tab. Each test here is one way the saved layout could be lost or replaced, and what keeps it.
///
/// Nothing here starts tmux: names come from `MacLocalTmuxTests.FakeServer`, and tests that swap
/// `MacLocalTmux.server` never suspend while it is in place.
extension LocalTmuxServerSuites {
@MainActor
@Suite("Terminal layouts that survive a crash", .serialized)
struct MacWorkspaceRestorationTests {
    private let prefix = UserDefaultsKeys.macWorkspaceRestoration

    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suite = "MacWorkspaceRestorationTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, suite)
    }

    private func tabKey(_ id: UUID) -> String { "\(prefix).\(id.uuidString.lowercased())" }
    private func windowKey(_ id: UUID) -> String { "\(prefix).window.\(id.uuidString.lowercased())" }

    /// Every workspace record in the suite, and nothing from the global domain.
    private func savedKeys(_ defaults: UserDefaults, _ suite: String) -> Set<String> {
        Set((defaults.persistentDomain(forName: suite) ?? [:]).keys.filter { $0.hasPrefix(prefix + ".") })
    }

    private func savedTab(_ defaults: UserDefaults, _ id: UUID) -> MacWorkspaceRestorationState? {
        defaults.data(forKey: tabKey(id)).flatMap { try? JSONDecoder().decode(MacWorkspaceRestorationState.self, from: $0) }
    }

    private func savedWindow(_ defaults: UserDefaults, _ id: UUID) -> MacWorkspaceWindowRestorationState? {
        defaults.data(forKey: windowKey(id)).flatMap { try? JSONDecoder().decode(MacWorkspaceWindowRestorationState.self, from: $0) }
    }

    // MARK: How a layout was lost

    @Test("a window a tab was moved into comes back with that tab after a relaunch, not an empty one")
    func movedTabWindowSurvivesRelaunch() throws {
        try withDefaults { defaults, _ in
            let broker = MacWorkspaceTransferBroker(capacity: 2, expiration: .seconds(30))
            let source = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: UUID(), tabs: [
                    MacWorkspaceTabRequest(initialPaneIntent: .local),
                    MacWorkspaceTabRequest(initialPaneIntent: .local, tabLabel: "Moved"),
                ]),
                transferBroker: broker, defaults: defaults)
            source.select(source.tabs[1].workspaceID)
            let moved = source.selectedTab
            let layout = moved.state
            let request = try #require(source.transferSelectedTab())
            let destination = MacWorkspaceWindowController(request: request, transferBroker: broker, defaults: defaults)
            #expect(destination.selectedTab === moved)

            // A crash: the ticket died with the process, and macOS hands the window its request again.
            let relaunched = MacWorkspaceWindowController(
                request: request, transferBroker: MacWorkspaceTransferBroker(), defaults: defaults)
            #expect(relaunched.tabs.map(\.workspaceID) == [moved.workspaceID], "the moved tab, not a new empty one")
            #expect(relaunched.selectedTab.state == layout)
            #expect(savedWindow(defaults, request.windowID)?.tabs.map(\.id) == [moved.workspaceID],
                    "the window's record still holds the moved tab")
        }
    }

    @Test("a window record that can't be read is left exactly as it was")
    func unreadableWindowRecordIsKept() throws {
        try withDefaults { defaults, _ in
            let id = UUID()
            let unreadable = Data("{\"schemaVersion\":1,\"tabs\":[".utf8)
            defaults.set(unreadable, forKey: windowKey(id))
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: id, tabs: []), defaults: defaults)
            #expect(window.tabs.count == 1)
            #expect(window.selectedTab.isEmpty)
            #expect(window.selectedTab.localRuntimesByPaneID.isEmpty)
            #expect(defaults.data(forKey: windowKey(id)) == unreadable)
        }
    }

    @Test("a tab whose saved layout can't be read keeps it, even when a pane is added")
    func unreadableTabRecordIsKept() throws {
        try withDefaults { defaults, _ in
            let id = UUID()
            // A pane naming a tmux session the decoder refuses (`MacWorkspacePaneIntent`'s check of
            // `localTmuxSession`): the whole layout fails to load.
            var object = try #require(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(MacWorkspaceRestorationState(id: id, initialIntent: .local))) as? [String: Any])
            var root = try #require(object["root"] as? [String: Any])
            var pane = try #require(root["pane"] as? [String: Any])
            var inner = try #require(pane["_0"] as? [String: Any])
            var intent = try #require(inner["intent"] as? [String: Any])
            intent["localTmuxSession"] = "work.1"
            inner["intent"] = intent
            pane["_0"] = inner
            root["pane"] = pane
            object["root"] = root
            let unreadable = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            defaults.set(unreadable, forKey: tabKey(id))

            let tab = MacWorkspaceController(request: MacWorkspaceTabRequest(workspaceID: id), defaults: defaults)
            #expect(tab.isEmpty)
            #expect(tab.localRuntimesByPaneID.isEmpty)
            // The toolbar's New Local Pane, or the empty tab's chooser.
            tab.addPane(intent: .local, axis: .horizontal)
            #expect(defaults.data(forKey: tabKey(id)) == unreadable)
        }
    }

    @Test("a tab closed after its last terminal ended leaves no empty layout behind for its window")
    func closedTabLeavesNoEmptyLayout() throws {
        try withDefaults { defaults, _ in
            let sessionManager = SessionManager(loadImmediately: false)
            // ⌘N: the window's first tab has the window's id.
            let request = MacWorkspaceLaunchRequest(initialPaneIntent: .local)
            let window = MacWorkspaceWindowController(request: request, defaults: defaults)
            let tab = window.tabs[0]
            let pane = try #require(tab.focusedPaneID)
            tab.focus(pane)
            // The shell exited: its pane goes, and with it the tab and the window.
            tab.removePane(pane, sessionManager: sessionManager)
            #expect(window.removeTab(tab.workspaceID, sessionManager: sessionManager))
            #expect(defaults.data(forKey: tabKey(tab.workspaceID)) == nil, "no empty layout left to restore")

            // A crash restores the window from its request regardless.
            let restored = MacWorkspaceWindowController(request: request, defaults: defaults)
            #expect(!restored.selectedTab.isEmpty, "not an empty New Terminal tab")
            restored.closeAllSessions(sessionManager: sessionManager)
        }
    }

    @Test("a window controller that is made and never shown writes nothing")
    func unshownWindowWritesNothing() throws {
        try withDefaults { defaults, suite in
            _ = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(startsEmpty: true), defaults: defaults)
            _ = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(initialPaneIntent: .local), defaults: defaults)
            _ = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: UUID(), tabs: []), defaults: defaults)
            #expect(savedKeys(defaults, suite).isEmpty, "wrote \(savedKeys(defaults, suite).sorted())")
        }
    }

    @Test("restoring a tab twice never rewrites its saved tmux session from the copy")
    func unshownCopyKeepsTheSavedSession() throws {
        try withDefaults { defaults, _ in
            let fake = MacLocalTmuxTests.FakeServer()
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }
            // Saved before tmux was on: a local pane with no session yet.
            let id = UUID()
            let saved = MacWorkspaceRestorationState(id: id, initialIntent: .local)
            let data = try JSONEncoder().encode(saved)
            defaults.set(data, forKey: tabKey(id))
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)

            let copy = MacWorkspaceController(request: MacWorkspaceTabRequest(workspaceID: id), defaults: defaults)
            #expect(copy.state.root?.panes.first?.intent.localTmuxSession != nil, "the copy chose a session")
            #expect(defaults.data(forKey: tabKey(id)) == data, "but saved nothing: no window shows it")
        }
    }

    // MARK: What keeps a layout

    @Test("a tab that couldn't be restored says so, saves nothing, and closing it discards its record")
    func unrestoredTabSaysSoAndClosesOnPurpose() throws {
        try withDefaults { defaults, _ in
            let id = UUID()
            let unreadable = Data("{\"id\":\"not a layout\"".utf8)
            defaults.set(unreadable, forKey: tabKey(id))
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: UUID(), tabs: [
                    MacWorkspaceTabRequest(workspaceID: id, tabLabel: "Build"),
                    MacWorkspaceTabRequest(initialPaneIntent: .local),
                ]), defaults: defaults)
            window.windowDidOpen()
            let tab = window.tabs[0]
            #expect(tab.restorationFailure == "Its saved layout couldn't be read.")
            #expect(tab.isEmpty && !tab.canAddPane, "nothing can be added over it")
            #expect(tab.windowIdentity(servers: []).title == "Build")
            #expect(defaults.data(forKey: tabKey(id)) == unreadable)

            window.select(id)
            window.renameTab(id, to: "Renamed")
            #expect(defaults.data(forKey: tabKey(id)) == unreadable, "the window saving around it leaves it alone")
            #expect(savedWindow(defaults, window.windowID)?.tabs.map(\.id).contains(id) == true)

            #expect(!window.removeTab(id, sessionManager: SessionManager(loadImmediately: false)))
            #expect(defaults.data(forKey: tabKey(id)) == nil, "closed on purpose")
        }
    }

    @Test("an empty layout never replaces one with panes unless the last pane was closed")
    func emptyLayoutNeverReplacesPanesUnasked() throws {
        try withDefaults { defaults, _ in
            let id = UUID()
            // Made before the tab's layout was first saved, as SwiftUI's discarded copies were.
            let early = MacWorkspaceController(
                request: MacWorkspaceTabRequest(workspaceID: id, startsEmpty: true), defaults: defaults)
            let shown = MacWorkspaceController(
                request: MacWorkspaceTabRequest(workspaceID: id, initialPaneIntent: .local), defaults: defaults)
            let pane = try #require(shown.focusedPaneID)
            shown.focus(pane)
            early.saveIfUnsaved()
            #expect(savedTab(defaults, id)?.root?.paneIDs == [pane], "the copy's empty layout did not replace it")

            shown.removePane(pane, sessionManager: SessionManager(loadImmediately: false))
            #expect(savedTab(defaults, id) != nil)
            #expect(savedTab(defaults, id)?.root == nil, "closing the last pane does")
        }
    }

    @Test("a window keeps one earlier generation of its tabs and comes back from it when its record can't be read")
    func previousGenerationRestoresAnUnreadableWindow() throws {
        try withDefaults { defaults, suite in
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(initialPaneIntent: .local), defaults: defaults)
            window.windowDidOpen()
            let first = window.tabs[0].workspaceID
            #expect(defaults.data(forKey: windowKey(window.windowID) + ".previous") == nil, "nothing earlier yet")
            let added = try #require(window.addTab())
            window.select(first)
            window.select(added.workspaceID)
            let previous = try #require(defaults.data(forKey: windowKey(window.windowID) + ".previous"))
            let earlier = try JSONDecoder().decode(MacWorkspaceWindowRestorationState.self, from: previous)
            #expect(earlier.tabs.map(\.id) == [first], "the generation before the tabs changed, not before a selection")
            #expect(savedKeys(defaults, suite).filter { $0.hasSuffix(".previous") }.count == 1, "one, bounded")

            // A bad write: the record can no longer be read.
            defaults.set(Data("{".utf8), forKey: windowKey(window.windowID))
            #expect(MacWorkspaceWindowController.hasSavedState(windowID: window.windowID, defaults: defaults))
            let restored = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: window.windowID, tabs: []), defaults: defaults)
            #expect(restored.restorationFailure == nil)
            #expect(restored.tabs.map(\.workspaceID) == [first])
            #expect(!restored.selectedTab.isEmpty)

            let sessionManager = SessionManager(loadImmediately: false)
            #expect(restored.removeTab(first, sessionManager: sessionManager))
            #expect(defaults.data(forKey: windowKey(window.windowID)) == nil)
            #expect(defaults.data(forKey: windowKey(window.windowID) + ".previous") == nil, "closed: nothing kept")
            window.closeAllSessions(sessionManager: sessionManager)
        }
    }

    @Test("a window whose tabs can't be read at all says so, adds nothing, and closing it discards the record")
    func unreadableWindowSaysSoAndClosesOnPurpose() throws {
        try withDefaults { defaults, _ in
            let id = UUID()
            let unreadable = Data("[]".utf8)
            defaults.set(unreadable, forKey: windowKey(id))
            #expect(!MacWorkspaceWindowController.hasSavedState(windowID: id, defaults: defaults))
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: id, tabs: []), defaults: defaults)
            window.windowDidOpen()
            #expect(window.restorationFailure != nil)
            #expect(window.selectedTab.restorationFailure == window.restorationFailure)
            #expect(!window.canAddTab && window.addTab() == nil)
            window.select(window.selectedTabID)
            #expect(defaults.data(forKey: windowKey(id)) == unreadable)
            #expect(window.removeTab(window.selectedTabID, sessionManager: SessionManager(loadImmediately: false)))
            #expect(defaults.data(forKey: windowKey(id)) == nil, "closed on purpose")
        }
    }

    @Test("a window restored as it was saved writes nothing when it opens")
    func restoredWindowOpensWithoutWriting() throws {
        try withDefaults { defaults, suite in
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(initialPaneIntent: .local), defaults: defaults)
            window.windowDidOpen()
            let saved = (defaults.persistentDomain(forName: suite) ?? [:]).filter { $0.key.hasPrefix(prefix) }
            #expect(saved.count == 2, "the window and its tab")

            let restored = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: window.windowID, tabs: []), defaults: defaults)
            restored.windowDidOpen()
            let after = (defaults.persistentDomain(forName: suite) ?? [:]).filter { $0.key.hasPrefix(prefix) }
            #expect(NSDictionary(dictionary: after).isEqual(to: saved))
        }
    }

    // MARK: Sessions still running at launch

    /// A tmux that counts how often it is asked, and answers with `reply`.
    private func countingServer(_ reply: String?, asked: @escaping @Sendable () -> Void) -> MacLocalTmux.Server {
        MacLocalTmux.Server(executablePath: { TmuxStandIn.path },
                            listSessions: { _ in asked(); return reply },
                            kill: { _, _ in }, detachClients: { _, _ in }, scroll: { _, _, _ in })
    }

    @Test("with tmux off, nothing is asked and nothing offered")
    func offerNeedsTmuxOn() throws {
        try withDefaults { defaults, _ in
            let asked = AskCount()
            let previous = MacLocalTmux.server
            MacLocalTmux.server = countingServer("glass-1\t0\t1\t1790000000") { asked.add() }
            defer { MacLocalTmux.server = previous }
            let offer = MacLocalTmuxLaunchOffer()
            #expect(offer.take(shown: [], defaults: defaults) == nil)
            #expect(asked.value == 0, "tmux was not run")
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            #expect(MacLocalTmuxLaunchOffer().take(shown: [], defaults: defaults) == ["glass-1"])
            #expect(asked.value == 1, "and is, once it is on")
        }
    }

    @Test("a list tmux can't give or that can't be read offers nothing rather than a guess")
    func offerNeedsAReadableList() throws {
        try withDefaults { defaults, _ in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let previous = MacLocalTmux.server
            defer { MacLocalTmux.server = previous }
            for reply in [nil, "glass-1_0_1_1790000000"] as [String?] {
                MacLocalTmux.server = countingServer(reply) {}
                #expect(MacLocalTmuxLaunchOffer().sessions(shown: [], defaults: defaults).isEmpty)
            }
        }
    }

    @Test("the offer: Glass's sessions running that no tab shows and none was closed on, in order, once")
    func offerListsSessionsLeftRunning() throws {
        try withDefaults { defaults, _ in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let fake = MacLocalTmuxTests.FakeServer()
            fake.running = ["glass-10", "glass-1", "glass-2", "glass-9", "glass-3", "work"]
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }

            let offer = MacLocalTmuxLaunchOffer()
            offer.noteClosed("glass-3")
            #expect(offer.take(shown: ["glass-2"], defaults: defaults) == ["glass-1", "glass-9", "glass-10"],
                    "not the user's own session, the one shown, or the one closed")
            #expect(offer.take(shown: [], defaults: defaults) == nil, "once")
            #expect(MacLocalTmuxLaunchOffer.message(count: 14) == "14 terminal sessions are still running. Reopen them?")
            #expect(MacLocalTmuxLaunchOffer.message(count: 1) == "1 terminal session is still running. Reopen it?")

            fake.running = ["glass-4"]
            #expect(MacLocalTmuxLaunchOffer().take(shown: ["glass-4"], defaults: defaults) == nil, "nothing to offer")
        }
    }

    @Test("sessions a window shows or is opening count as shown; a tab closed in tmux counts as closed")
    func shownAndClosedSessions() throws {
        try withDefaults { defaults, _ in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let fake = MacLocalTmuxTests.FakeServer()
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(initialPaneIntent: .local), defaults: defaults)
            let pane = try #require(window.selectedTab.focusedPaneID)
            let name = try #require(window.selectedTab.localTmuxSession(for: pane))
            let registry = MacWorkspacePreviewRegistry()
            let shownWindow = NSWindow()
            shownWindow.isReleasedWhenClosed = false
            registry.register(window, window: shownWindow)
            #expect(MacLocalTmuxLaunchOffer.shownSessions(registry: registry).contains(name))

            window.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
            #expect(MacLocalTmuxLaunchOffer.shared.closedThisRun.contains(name))
        }
    }

    @Test("Reopen: one window, a tab per session in order, each attached to its session")
    func reopenOpensOneWindowOfSessions() throws {
        try withDefaults { defaults, _ in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let fake = MacLocalTmuxTests.FakeServer()
            let names = ["glass-1", "glass-4", "glass-12"]
            fake.running = Set(names)
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }

            let requests = MacLocalTmuxLaunchOffer.launchRequests(for: names)
            #expect(requests.count == 1)
            let request = try #require(requests.first)
            let window = MacWorkspaceWindowController(request: request, defaults: defaults)
            #expect(window.tabs.map { $0.focusedPane?.intent.localTmuxSession } == names)
            #expect(window.selectedTabID == window.tabs[0].workspaceID)

            let many = (1...33).map { "glass-\($0)" }
            #expect(MacLocalTmuxLaunchOffer.launchRequests(for: many).map(\.tabs.count) == [32, 1])
            #expect(MacLocalTmuxLaunchOffer.launchRequests(for: []).isEmpty)
        }
    }
}

private nonisolated final class AskCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}
}
#endif
