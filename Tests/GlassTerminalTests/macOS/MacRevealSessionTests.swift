//
//  MacRevealSessionTests.swift
//  Glass Power Tools — GlassTerminalTests (macOS)
//
//  B-X24: Files' Insert Path typed the paths into its terminal and left the Files window in front.
//  It now brings that terminal forward, which is what Active's Show does too: the window, its tab,
//  and the pane the session is in, so what was typed goes on from there.
//

#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GlassTerminal

@MainActor
@Suite("A terminal brought forward by its session: window, tab and pane", .serialized)
struct MacRevealSessionTests {
    @Test("the session's window comes forward, on its tab, with its pane focused")
    func revealsWindowTabAndPane() throws {
        let suite = "MacRevealSessionTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        let session = TerminalSession(server: server, terminalWriteSink: { _ in })
        let broker = MacLiveSessionBroker()
        let ticket = broker.issue(session: session) {}
        let request = MacWorkspaceLaunchRequest(tabs: [MacWorkspaceTabRequest(
            initialPaneIntent: .ssh(serverID: server.id), liveSessionTicketID: ticket)])
        let window = MacWorkspaceWindowController(request: request, liveSessionBroker: broker, defaults: defaults)
        let shownTab = try #require(window.tabs.first)
        let pane = try #require(shownTab.focusedPaneID)
        #expect(shownTab.sessionsByPaneID[pane] === session)
        // Elsewhere since: another pane focused in its tab, another tab chosen.
        shownTab.addPane(intent: .local, axis: .horizontal)
        #expect(shownTab.focusedPaneID != pane)
        _ = try #require(window.addTab())
        #expect(window.selectedTabID != shownTab.workspaceID)

        let registry = MacWorkspacePreviewRegistry()
        let onScreen = NSWindow()
        onScreen.isReleasedWhenClosed = false
        registry.register(window, window: onScreen)
        var presented: [NSWindow] = []
        #expect(registry.reveal(sessionID: session.id, present: { presented.append($0) }))
        #expect(window.selectedTabID == shownTab.workspaceID, "its tab is selected")
        #expect(shownTab.focusedPaneID == pane, "on the pane the session is in")
        #expect(presented.count == 1 && presented.first === onScreen, "and its window comes forward")
        #expect(!registry.reveal(sessionID: UUID(), present: { _ in Issue.record("no window shows it") }))
        for tab in window.tabs { tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
    }
}
#endif
