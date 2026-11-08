import Foundation
import Testing
import GlassLayers
@testable import GlassTerminal

/// A Vision Pro window shown again brings its terminals back (2026-11-01). The owner had named a
/// window, and both its terminals said "Disconnected" and did not reconnect as he opened it: on
/// Vision Pro nothing connected a terminal that was down as its window was shown, a shell that
/// ended while the window was in the dock left its tab behind, and choosing a reopened window's
/// terminal in Active did nothing.
///
/// Nothing connects here: the session manager records what it is asked to connect.
@MainActor
@Suite("A window shown brings its terminals back")
struct ShownTerminalsReconnectTests {
    final class RecordingManager: SessionManager {
        var asked: [UUID] = []
        override func connectWhenShown(_ session: TerminalSession, settingsManager: SettingsManager) async throws {
            asked.append(session.id)
            session.state = .connecting
        }
    }

    private func server(_ name: String) -> ServerConfiguration {
        ServerConfiguration(name: name, host: "192.0.2.10", username: "ann")
    }

    private func withManager(_ servers: [ServerConfiguration],
                             _ body: (RecordingManager, SettingsManager) async throws -> Void) async throws {
        let suite = "ShownTerminalsReconnect.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let serverManager = ServerManager(loadImmediately: false, defaults: defaults,
                                          passwordStore: ServerPasswordStore(retrieve: { _ in "unused" }, save: { _, _ in }, delete: { _ in }))
        serverManager.servers = servers
        let manager = RecordingManager(serverManager: serverManager, loadImmediately: false)
        try await body(manager, SettingsManager(loadImmediately: false, settingsDefaults: defaults))
    }

    @Test("a window shown connects its terminals that are down, and none disconnected by hand, ended or on its way")
    func connectsTheDroppedOnes() async throws {
        let alpha = server("alpha"), beta = server("beta")
        try await withManager([alpha, beta]) { manager, settings in
            let window = UUID()
            manager.createWorkgroup(id: window, name: "Work", colorTag: .blue)
            defer { manager.closeWorkgroup(window) }
            @MainActor func terminal(_ on: ServerConfiguration) -> TerminalSession {
                let session = TerminalSession(server: on)
                manager.registerSession(session)
                #expect(manager.appendSession(session, toWorkgroup: window))
                return session
            }
            let neverConnected = terminal(alpha)
            let lost = terminal(alpha)
            lost.state = .error("The connection stopped answering")
            let byHand = terminal(beta)
            byHand.disconnect()
            let ended = terminal(beta)
            ended.handleCleanRemoteExit()
            let onItsWay = terminal(beta)
            onItsWay.state = .reconnecting
            let otherMachine = terminal(beta)

            _ = await TerminalWorkgroupOpening.connectDropped(inWorkgroup: window, sessionManager: manager,
                                                              settingsManager: settings)
            #expect(Set(manager.asked) == [neverConnected.id, lost.id, otherMachine.id])
            #expect(manager.asked.filter { [neverConnected.id, lost.id].contains($0) } == [neverConnected.id, lost.id],
                    "one machine's in turn, so the second shares the first one's connection")

            // Shown again: those on their way now are left to finish.
            _ = await TerminalWorkgroupOpening.connectDropped(inWorkgroup: window, sessionManager: manager,
                                                              settingsManager: settings)
            #expect(manager.asked.count == 3)
        }
    }

    @Test("a shell that ended is never connected again as it is shown; a lost one is, and connecting starts afresh")
    func anEndedShellStaysEnded() async {
        let ended = TerminalSession(server: server("alpha"))
        ended.handleCleanRemoteExit()
        #expect(ended.shellEnded && ended.isDown && !ended.connectsOnShow)

        let lost = TerminalSession(server: server("alpha"))
        lost.state = .error("The connection to the server closed")
        #expect(!lost.shellEnded && lost.connectsOnShow)

        // Connected again by hand (Reconnect): no longer ended. Here it fails before reaching the
        // network, having nothing to sign in with.
        await ended.connect()
        #expect(!ended.shellEnded && ended.connectsOnShow)
    }

    @Test("a terminal that can't be connected as it is shown says why, in the terminal")
    func sayingWhy() async throws {
        try await withManager([server("alpha")]) { recording, settings in
            let manager = SessionManager(serverManager: recording.serverManager, loadImmediately: false)
            // Not one the manager knows: it can't say how to sign in.
            let stranger = TerminalSession(server: recording.serverManager.servers[0])
            await #expect(throws: (any Error).self) {
                try await manager.connectWhenShown(stranger, settingsManager: settings)
            }
            guard case .error(let message) = stranger.state else {
                Issue.record("it stayed \(stranger.state.displayName), saying nothing")
                return
            }
            #expect(!message.isEmpty)
        }
    }

    @Test("choosing a reopened window's dropped terminal in Active reconnects it where windows show every terminal")
    func activeReconnectsAReopenedTerminal() {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let slot = TerminalSession(server: server("alpha"))
        slot.tmuxSessionName = "glass-3"
        slot.isWorkgroupSlot = true
        slot.state = .error("The connection stopped answering")
        #if os(iOS)
        // iPhone and iPad show one terminal of a window at a time, and a slot connects as it is
        // shown (`connectShownSlot`, W4b): choosing it shows it, and nothing is asked here.
        #expect(TerminalWorkgroupOpening.slotsConnectWhenShown)
        GlassTerminalCapability.reconnectIfDropped(slot, runtime: runtime)
        #expect(runtime.takeRequests().isEmpty, "a slot here connects as it is shown")
        #else
        #expect(!TerminalWorkgroupOpening.slotsConnectWhenShown, "this platform shows every terminal of a window")

        GlassTerminalCapability.reconnectIfDropped(slot, runtime: runtime)
        let asked = runtime.takeRequests().compactMap { request -> UUID? in
            if case .reconnect(let id) = request { id } else { nil }
        }
        #expect(asked == [slot.id])

        slot.handleCleanRemoteExit()
        GlassTerminalCapability.reconnectIfDropped(slot, runtime: runtime)
        #expect(runtime.takeRequests().isEmpty, "one whose shell ended is not brought back")
        #endif
    }
}
