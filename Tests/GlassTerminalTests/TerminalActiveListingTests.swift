import Foundation
import Testing
import GlassLayers
import GlassConnectionKit
import GlassShell
import SwiftUI
@testable import GlassTerminal

/// A live terminal in no workgroup — every terminal Connect opens on a Mac — is a row in Active,
/// on its machine (2026-09-22: the MySQL session on alpha was listed and the terminal beside it
/// was not).
@Suite("Active lists a terminal that is in no workgroup")
@MainActor
struct TerminalActiveListingTests {
    private func session(named name: String) -> TerminalSession {
        TerminalSession(server: ServerConfiguration(name: name, host: "example.invalid", port: 22, username: "casey"))
    }

    @Test("A lone session is one row, on its server's endpoint; grouped, it is the workgroup's row")
    func loneSessionIsListed() {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let session = session(named: "alpha")
        manager.registerSession(session)
        session.state = .connected

        let lone = capability.openSessions()
        #expect(lone.map(\.id) == [GlassTerminalCapability.sessionID(sessionID: session.id)])
        #expect(lone.first?.title == "alpha")
        #expect(lone.first?.endpointIDs == [EndpointID(rawValue: session.server.id)], "on its machine")

        let group = manager.createWorkgroup(name: "alpha", colorTag: .blue)
        #expect(manager.appendSession(session, toWorkgroup: group))
        let grouped = capability.openSessions()
        #expect(grouped.map(\.id) == [GlassTerminalCapability.sessionID(workgroupID: group)], "once, as the workgroup")
        manager.closeWorkgroup(group)
    }

    /// All Windows on iPhone and iPad draws a terminal's card on what its window paints behind it —
    /// the theme's canvas, an opaque page — in the theme's light or dark, whatever the system's (the
    /// owner, 2026-10-17, light mode: a dark theme's picture was green text on the white sheet).
    @Test("A terminal's cards carry its theme's canvas and its light or dark")
    func cardsCarryTheThemesBackdrop() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let group = manager.createWorkgroup(name: "alpha", colorTag: .blue)
        defer { manager.closeWorkgroup(group) }
        let terminal = session(named: "alpha")
        manager.registerSession(terminal)
        terminal.state = .connected
        _ = manager.appendSession(terminal, toWorkgroup: group)

        runtime.settingsManager.currentTheme.background = CodableColor(sRGBRed: 0.05, green: 0.05, blue: 0.08, alpha: 0.2)
        let window = try #require(capability.openSessions().first)
        let card = try #require(window.tabs.first)
        let dark = GlassSessionBackdrop(color: CodableColor(sRGBRed: 0.05, green: 0.05, blue: 0.08, alpha: 1).color,
                                        colorScheme: .dark)
        #expect(window.backdrop?() == dark, "the window's card")
        #expect(card.backdrop?() == dark, "a tab's card: opaque, as the window's page is, whatever the theme's alpha")

        runtime.settingsManager.currentTheme.background = CodableColor(sRGBRed: 0.98, green: 0.97, blue: 0.94, alpha: 1)
        runtime.settingsManager.currentTheme.preferredAppearance = .light
        #expect(card.backdrop?()?.colorScheme == .light, "a light theme's card is drawn light")
    }

    @Test("A workgroup Connect made for one terminal is named as its window names it; a named workgroup keeps its name")
    func connectWorkgroupTakesTheTerminalsName() {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        func open(_ server: String, inWorkgroup name: String, count: Int = 1) -> (UUID, [TerminalSession]) {
            let group = manager.createWorkgroup(name: name, colorTag: .blue)
            let sessions = (0..<count).map { _ in session(named: server) }
            for session in sessions {
                manager.registerSession(session)
                session.state = .connected
                _ = manager.appendSession(session, toWorkgroup: group)
            }
            return (group, sessions)
        }
        func title(_ group: UUID) -> String? {
            capability.openSessions().first { $0.id == GlassTerminalCapability.sessionID(workgroupID: group) }?.title
        }

        // As Connect makes it on iPhone and Vision Pro: named after the server.
        let (connected, terminals) = open("Terminal on alpha", inWorkgroup: "Terminal on alpha")
        #expect(title(connected) == "Terminal on alpha", "nothing names the terminal yet: the server")
        terminals[0].rename(to: "Glass Power Tools")
        #expect(title(connected) == "Glass Power Tools",
                "the owner, on the Vision Pro: Active said \"Terminal on …\" while the window had the name")

        let (named, inNamed) = open("Terminal on bravo", inWorkgroup: "Backend")
        inNamed[0].rename(to: "api")
        #expect(title(named) == "Backend", "a workgroup with a name of its own keeps it")

        let (several, _) = open("Terminal on charlie", inWorkgroup: "Terminal on charlie", count: 2)
        #expect(title(several) == "Terminal on charlie", "several terminals: the workgroup's name")
        for group in [connected, named, several] { manager.closeWorkgroup(group) }
    }

    @Test("W6: a machine skipped because asking would need something says why, in plain words")
    func skippedMachinesSayWhy() {
        let server = ServerConfiguration(name: "alpha", host: "alpha.example.com", port: 22, username: "casey")
        #expect(TerminalListingSkip.classify(SessionOpenError.missingPassword(server: server, location: .target)).reason
                == "Not checked: signing in would need your password.")
        #expect(TerminalListingSkip.classify(SessionOpenError.credentialUnavailable(server: server, location: .target)) == .locked)
        #expect(TerminalListingSkip.classify(SessionOpenError.sshKeyNotFound(server: server, location: .target)) == .keyUnavailable)
        #expect(TerminalListingSkip.classify(TerminalListingSkip.identityUnconfirmed).reason
                == "Not checked: connect once to confirm it's the right machine.")
        #expect(TerminalListingSkip.classify(SSHError.connectionFailed).reason
                == "Not checked: the connection failed. Connect to it to see why.")
        #expect(TerminalListingSkip.connectionFailed.errorDescription == "The connection failed. Connect to it to see why.",
                "ending a session there says the same, without the note's prefix")

        let capability = GlassTerminalCapability(runtime: GlassTerminalRuntime(layers: GlassLayerStore.forTest()))
        let report = capability.runningReport(local: nil, hosts: [(server, .skipped(TerminalListingSkip.needsPassword.reason))])
        #expect(report.sessions.isEmpty)
        #expect(report.unchecked.map(\.endpointID) == [EndpointID(rawValue: server.id)])
        #expect(report.unchecked.first?.reason == "Not checked: signing in would need your password.")
    }

    @Test("D86: a server that is This Mac's own machine isn't listed over SSH: its sessions are This Mac's")
    func thisMacsMachineListedOnce() {
        let server = ServerConfiguration(name: "alpha", host: "192.0.2.10", port: 22, username: "casey")
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let listed = TerminalTmux.Session(name: "glass-1", attachedClients: 0, windows: 1, lastActivity: nil)
        #expect(capability.runningReport(local: nil, hosts: [(server, .sessions([listed]))]).sessions.count == 1,
                "any other machine's session is a row")
        runtime.isThisMacServer = { $0 == server.id }
        #expect(capability.runningReport(local: nil, hosts: [(server, .sessions([listed]))]).sessions.isEmpty)
    }

    @Test("Closing a lone session's row ends the session")
    func closeEndsTheSession() {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let session = session(named: "alpha")
        manager.registerSession(session)
        capability.openSessions().first?.close()
        #expect(manager.sessions.isEmpty)
    }

    /// All Windows off the Mac (the owner, 2026-10-14): "Grouped by machine, but show each tab as a card."
    @Test("A workgroup's terminals are its tabs: named as their tabs are, each on its server; chosen, a tab comes back selected")
    func workgroupTabsAreCards() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let group = manager.createWorkgroup(name: "Backend", colorTag: .blue)
        let api = session(named: "alpha"), logs = session(named: "bravo")
        for terminal in [api, logs] {
            manager.registerSession(terminal)
            terminal.state = .connected
            #expect(manager.appendSession(terminal, toWorkgroup: group))
        }
        api.rename(to: "api")

        let window = try #require(capability.openSessions().first { $0.id == GlassTerminalCapability.sessionID(workgroupID: group) })
        #expect(window.tabs.map(\.title) == ["api", "bravo"], "named as each tab is")
        #expect(window.tabs.map(\.endpointIDs) == [[EndpointID(rawValue: api.server.id)], [EndpointID(rawValue: logs.server.id)]],
                "each on its own machine")
        #expect(window.tabs.map(\.id) == [api.id, logs.id].map(GlassTerminalCapability.tabID(sessionID:)))
        _ = runtime.takeRequests()

        window.tabs[0].activate()
        #expect(manager.workgroup(for: group)?.selectedSessionID == api.id, "the window comes back on the tab chosen")
        let requests = runtime.takeRequests()
        #expect(requests.count == 1)
        if case .showWorkgroup(let shown)? = requests.first { #expect(shown == group) } else { Issue.record("not shown: \(requests)") }

        window.tabs[1].close()
        #expect(manager.workgroup(for: group)?.sessionIDs == [api.id], "closing a tab's card closes that tab")
        manager.closeWorkgroup(group)
    }

    /// The owner, on the iPhone (2026-10-24): each tab whose connection had dropped was listed
    /// twice — "Disconnected · in tmux (Terminal 1)", and its session again below it, "Open
    /// elsewhere", where Open made a second tab on it.
    @Test("A dropped tab holds its session: listed once, as the tab, saying what the machine said")
    func aDroppedTabStandsForItsSession() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let terminal = session(named: "alpha")
        manager.registerSession(terminal)
        let group = manager.createWorkgroup(name: "alpha", colorTag: .blue)
        #expect(manager.appendSession(terminal, toWorkgroup: group))
        terminal.tmuxSessionName = "glass-1"
        terminal.state = .disconnected
        let server = terminal.server
        let mine = TerminalTmux.Session(name: "glass-1", attachedClients: 1, windows: 1)
        let other = TerminalTmux.Session(name: "glass-2", attachedClients: 0, windows: 1)
        func row() throws -> GlassOpenSession {
            try #require(capability.openSessions().first { $0.id == GlassTerminalCapability.sessionID(workgroupID: group) })
        }
        #expect(try row().subtitle == "Disconnected · in tmux (Terminal 1)", "nothing asked of the machine yet")

        let report = capability.runningReport(local: nil, hosts: [(server, .sessions([mine, other]))])
        #expect(report.sessions.map(\.attachment?.name) == ["glass-1", "glass-2"])
        #expect(report.sessions.map { $0.isHeldHere() } == [true, false], "the tab's session is its row's, not one of its own")
        #expect(try row().subtitle == "Disconnected · Open elsewhere", "what the session's own row said")

        // A session of the same name on another machine is that machine's, not this tab's.
        let bravo = ServerConfiguration(name: "bravo", host: "bravo.example.invalid", port: 22, username: "casey")
        let elsewhere = capability.runningReport(local: nil, hosts: [(bravo, .sessions([mine]))])
        #expect(elsewhere.sessions.map { $0.isHeldHere() } == [false], "held only on the tab's own machine")

        // Detached, the session is a row of its own at once: nothing has to ask the machine again.
        manager.closeWorkgroup(group)
        #expect(report.sessions.map { $0.isHeldHere() } == [false, false])
    }

    @Test("A dropped tab whose session has ended says so; a live one is shown as it was")
    func aDroppedTabWhoseSessionEnded() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let terminal = session(named: "alpha")
        manager.registerSession(terminal)
        let group = manager.createWorkgroup(name: "alpha", colorTag: .blue)
        defer { manager.closeWorkgroup(group) }
        #expect(manager.appendSession(terminal, toWorkgroup: group))
        terminal.tmuxSessionName = "glass-1"
        terminal.state = .disconnected
        let other = TerminalTmux.Session(name: "glass-2", attachedClients: 0, windows: 1)

        _ = capability.runningReport(local: nil, hosts: [(terminal.server, .sessions([other]))])
        let window = try #require(capability.openSessions().first)
        #expect(window.subtitle == "Disconnected · its tmux session has ended")
        #expect(window.tabs.first?.subtitle == window.subtitle, "its card in All Windows says the same")

        // On its way back, it is listed as it always was, and its session is not listed again.
        terminal.state = .reconnecting
        let mine = TerminalTmux.Session(name: "glass-1", attachedClients: 1, windows: 1)
        let report = capability.runningReport(local: nil, hosts: [(terminal.server, .sessions([mine, other]))])
        #expect(report.sessions.map(\.attachment?.name) == ["glass-2"])
        #expect(capability.openSessions().first?.subtitle == "Reconnecting... · in tmux (Terminal 1)")
    }

    @Test("Choosing a dropped tab in tmux reconnects it; not one disconnected on purpose, a slot, or a plain shell")
    func choosingADroppedTabReconnectsIt() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let group = manager.createWorkgroup(name: "Backend", colorTag: .blue)
        defer { manager.closeWorkgroup(group) }
        let dropped = session(named: "alpha"), chosen = session(named: "bravo"), slot = session(named: "charlie"),
            plain = session(named: "delta")
        for terminal in [dropped, chosen, slot, plain] {
            manager.registerSession(terminal)
            #expect(manager.appendSession(terminal, toWorkgroup: group))
            terminal.state = .disconnected
        }
        dropped.tmuxSessionName = "glass-1"
        chosen.tmuxSessionName = "glass-2"
        chosen.disconnect()
        slot.tmuxSessionName = "glass-3"
        slot.isWorkgroupSlot = true
        slot.connectsWhenShown = true
        func reconnects(_ request: GlassTerminalRuntime.Request) -> UUID? {
            if case .reconnect(let id) = request { id } else { nil }
        }
        let window = try #require(capability.openSessions().first)
        _ = runtime.takeRequests()

        window.tabs[0].activate()
        #expect(runtime.takeRequests().compactMap(reconnects) == [dropped.id])
        for tab in window.tabs.dropFirst() {
            tab.activate()
            #expect(runtime.takeRequests().compactMap(reconnects).isEmpty, "\(tab.title)")
        }
        // The window's own row: its tab in front.
        _ = manager.selectSession(dropped.id, inWorkgroup: group)
        window.activate()
        #expect(runtime.takeRequests().compactMap(reconnects) == [dropped.id])
    }

    /// The owner (2026-10-15): "in the expose it show one card for all tabs". The iPhone opens a
    /// window's other tabs as slots that connect when shown; All Windows dropped them as
    /// disconnected.
    @Test("A tab that connects when it is shown waits, and says so; one that dropped does not")
    func slotTabsWaitToBeShown() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let group = manager.createWorkgroup(name: "Backend", colorTag: .blue)
        let api = session(named: "alpha"), logs = session(named: "bravo"), jobs = session(named: "charlie")
        for terminal in [api, logs, jobs] {
            manager.registerSession(terminal)
            #expect(manager.appendSession(terminal, toWorkgroup: group))
        }
        api.state = .connected
        logs.isWorkgroupSlot = true
        logs.connectsWhenShown = true
        logs.state = .disconnected
        jobs.state = .disconnected

        let window = try #require(capability.openSessions().first { $0.id == GlassTerminalCapability.sessionID(workgroupID: group) })
        #expect(window.tabs.map(\.waitsToBeShown) == [false, true, false])
        #expect(window.tabs[1].subtitle == "Connects when opened")
        #expect(window.tabs.map(\.connectedEndpointIDs.isEmpty) == [false, true, true],
                "waiting is not connected: All Windows lists it by `waitsToBeShown` (GlassShell's tests)")
        manager.closeWorkgroup(group)
    }
}
