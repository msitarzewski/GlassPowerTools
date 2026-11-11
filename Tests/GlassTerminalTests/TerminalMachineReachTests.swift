//
//  TerminalMachineReachTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A machine out of reach is the machine's failure, not each terminal's (the owner, 2026-11-10: dozens of tmux
//  terminals on a MacBook Pro asleep in a bag "try to connect, but time out, some show detached, as if they could be
//  reattached"). What must hold: a pass over a window's terminals dials a machine that doesn't answer once, and its
//  other terminals fail the same way without dialling, while a failure of one terminal's own stops nothing; a
//  machine on a tailnet with Tailscale off here is said at once, with its own title; the words say what happened; and
//  Active doesn't keep "Detached" for a machine it couldn't list.
//
//  Nothing connects: the session manager double records what it is asked to connect.
//

import Foundation
import Testing
import NIOCore
import GlassLayers
import GlassShell
import GlassSSHTransport
import GlasSecretStore
@testable import GlassTerminal

@MainActor
@Suite("A machine out of reach is the machine's failure")
struct TerminalMachineReachTests {
    /// Fails every connect it is asked for on `down` machines with `failure`, as `TerminalSession.connect` does, and
    /// connects every other.
    final class Manager: SessionManager {
        var asked: [UUID] = []
        var down: Set<UUID> = []
        var failure: any Error = ChannelError.connectTimeout(.seconds(15))
        override func connectWhenShown(_ session: TerminalSession, settingsManager: SettingsManager) async throws {
            asked.append(session.id)
            guard down.contains(session.server.id) else {
                session.state = .connected
                return
            }
            session.lastConnectFailure = TerminalConnectFailure(failure)
            session.state = .error(SSHConnection.userFacingMessage(for: failure, server: session.server))
        }
    }

    private func withManager(_ body: (Manager, SettingsManager) async throws -> Void) async throws {
        let suite = "TerminalMachineReach.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let serverManager = ServerManager(loadImmediately: false, defaults: defaults,
                                          passwordStore: ServerPasswordStore(retrieve: { _ in "unused" }, save: { _, _ in }, delete: { _ in }))
        let manager = Manager(serverManager: serverManager, loadImmediately: false)
        try await body(manager, SettingsManager(loadImmediately: false, settingsDefaults: defaults))
    }

    private let laptop = ServerConfiguration(name: "studio", host: "192.0.2.10", username: "ann")
    private let server = ServerConfiguration(name: "build", host: "192.0.2.20", username: "ann")

    private func terminals(_ count: Int, on machine: ServerConfiguration, in manager: SessionManager) -> [TerminalSession] {
        (0..<count).map { _ in
            let session = TerminalSession(server: machine)
            manager.registerSession(session)
            session.state = .error("The connection stopped answering")
            return session
        }
    }

    @Test("thirty terminals on a machine that doesn't answer: dialled once, all thirty told why; another machine untouched")
    func onePassDialsAMachineOnce() async throws {
        try await withManager { manager, settings in
            manager.down = [laptop.id]
            let onLaptop = terminals(30, on: laptop, in: manager)
            let onServer = terminals(2, on: server, in: manager)
            let failures = await TerminalWorkgroupOpening.connect(onLaptop + onServer, sessionManager: manager,
                                                                    settingsManager: settings)
            #expect(manager.asked.filter { id in onLaptop.contains { $0.id == id } }.count == 1, "the laptop dialled once")
            #expect(onServer.allSatisfy { $0.state == .connected }, "the other machine's terminals connect as before")
            let said = "studio at 192.0.2.10:22 didn't answer. It may be asleep, or off the network."
            #expect(onLaptop.allSatisfy { $0.state == .error(said) }, "each of the thirty says why")
            #expect(onLaptop.allSatisfy { $0.lastConnectFailure == .notAnswering })
            #expect(failures == ["studio: \(said)"], "said once for the machine")
        }
    }

    @Test("a failure of one terminal's own — the machine answered — stops nothing: each terminal is tried")
    func aTerminalsOwnFailureStopsNothing() async throws {
        try await withManager { manager, settings in
            manager.down = [laptop.id]
            manager.failure = SSHTransportError.authenticationFailed
            let onLaptop = terminals(5, on: laptop, in: manager)
            _ = await TerminalWorkgroupOpening.connect(onLaptop, sessionManager: manager, settingsManager: settings)
            #expect(manager.asked.count == 5)
            #expect(onLaptop.allSatisfy { $0.lastConnectFailure == .other })
        }
    }

    @Test("Tailscale off here stops a pass the same way, and the panel says to turn it on")
    func tailscaleOffStopsAPass() async throws {
        try await withManager { manager, settings in
            manager.down = [laptop.id]
            manager.failure = GlassTailscaleReach.Required(machine: "studio", host: "100.92.10.12")
            let onLaptop = terminals(4, on: laptop, in: manager)
            _ = await TerminalWorkgroupOpening.connect(onLaptop, sessionManager: manager, settingsManager: settings)
            #expect(manager.asked.count == 1)
            #expect(onLaptop.allSatisfy { $0.lastConnectFailure == .needsTailscale })
            #expect(onLaptop.allSatisfy { $0.connectionNotice?.title == "Tailscale Is Off" })
        }
    }

    @Test("connecting to a tailnet machine with Tailscale off here fails at once, with what to do")
    func tailnetMachineWithTailscaleOff() async throws {
        let saved = TerminalSession.interfaceAddresses
        defer { TerminalSession.interfaceAddresses = saved }
        TerminalSession.interfaceAddresses = { [.init(interface: "en0", address: "192.168.1.20")] }
        let session = TerminalSession(server: ServerConfiguration(name: "studio", host: "100.92.10.12", username: "ann"))
        let started = ContinuousClock.now
        await session.connect()
        #expect(ContinuousClock.now - started < .seconds(2), "no connect timeout waited out")
        #expect(session.lastConnectFailure == .needsTailscale)
        guard case .error(let message) = session.state else { Issue.record("not failed: \(session.state)"); return }
        #expect(message.hasPrefix("studio is on your tailnet (100.92.10.12), and Tailscale is off on this "))
        #expect(message.hasSuffix("Turn it on, then try again."))
        let notice = try #require(session.connectionNotice)
        #expect(notice.title == "Tailscale Is Off")
        #expect(notice.kind == .down, "with Reconnect, for once it's on")

        // On the tailnet, nothing is said of Tailscale: the connection goes on (here, to its missing credentials).
        TerminalSession.interfaceAddresses = { [.init(interface: "utun5", address: "100.92.10.11")] }
        let onTailnet = TerminalSession(server: ServerConfiguration(name: "studio", host: "100.92.10.12", username: "ann"))
        await onTailnet.connect()
        #expect(onTailnet.lastConnectFailure == .other)
    }

    #if os(macOS)
    /// The whole way, nothing doubled: the session manager, each terminal's connect, the pool and the SSH engine,
    /// dialling 192.0.2.10 — an address set aside for documentation (RFC 5737) that no machine answers. Ten terminals
    /// took ten connect timeouts, one after another; now one. The Mac only: on the iPhone and Vision Pro simulators a
    /// test process can't keep the password in the Keychain (`SecretStoreError`), so it never reaches the network
    /// there; `SSHMachineNotAnsweringTests` checks those platforms' network errors without one.
    @Test("ten terminals on a machine nothing answers, the real way: one timeout, not ten", .timeLimit(.minutes(2)))
    func realPassOverAMachineNothingAnswers() async throws {
        let suite = "TerminalMachineReach.real.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let serverManager = ServerManager(loadImmediately: false, defaults: defaults,
                                          passwordStore: ServerPasswordStore(retrieve: { _ in "unused" }, save: { _, _ in }, delete: { _ in }))
        let manager = SessionManager(serverManager: serverManager, loadImmediately: false)
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        let machine = ServerConfiguration(name: "studio", host: "192.0.2.10", username: "ann")
        let terminals = (0..<10).map { _ in
            let session = TerminalSession(server: machine)
            manager.registerTransientSession(session, password: "unused")
            return session
        }
        defer { for session in terminals { manager.closeSession(session) } }

        let started = ContinuousClock.now
        let failures = await TerminalWorkgroupOpening.connect(terminals, sessionManager: manager, settingsManager: settings)
        let took = ContinuousClock.now - started
        #expect(took < .seconds(25), "one connect timeout (15 s), not ten: took \(took)")
        #expect(terminals.allSatisfy { $0.lastConnectFailure == TerminalConnectFailure.notAnswering },
                "\(terminals.first.map { "\($0.state) — \($0.lastConnectionDiagnostics ?? "no diagnostics")" } ?? "")")
        #expect(failures == ["studio: studio at 192.0.2.10:22 didn't answer. It may be asleep, or off the network."])
    }
    #endif

    private struct AnyPassword: SSHCredentialResolver {
        func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
            .password(SecureBytes(Data("unused".utf8)))
        }
    }

    /// Every platform's own network stack, nothing doubled: the SSH engine dials 192.0.2.1 (RFC 5737, answered by no
    /// machine) and what it throws counts as the machine not answering, with its words. The iPhone and Vision Pro are
    /// where a sleeping Mac was seen; the whole pass above needs the Keychain, which their simulators' test process
    /// hasn't, so this is the check there.
    @Test("the network's own failure for a machine nothing answers counts as not answering, here",
          .timeLimit(.minutes(1)))
    func thisPlatformsNetworkFailure() async {
        let hop = SSHHop(displayName: "nobody", endpoint: SSHEndpoint(host: "192.0.2.1", port: 22, username: "ann"),
                         credential: .custom("test"))
        let transport = SSHTransport(route: SSHRoute(target: hop), credentials: AnyPassword(),
                                     trustStore: InMemoryHostTrustStore())
        let started = ContinuousClock.now
        do {
            try await transport.connect()
            Issue.record("connected to an address nothing answers")
        } catch {
            #expect(TerminalConnectFailure(error) == .notAnswering, "\(String(reflecting: error))")
            #expect(ContinuousClock.now - started < .seconds(20), "within the 15 s connect timeout")
            let unnamed = ServerConfiguration(name: "192.0.2.1", host: "192.0.2.1", username: "ann")
            #expect(SSHConnection.userFacingMessage(for: error, server: unnamed)
                    == "192.0.2.1:22 didn't answer. It may be asleep, or off the network.")
        }
    }

    @Test("what counts as the machine's failure, and the words for it")
    func classificationAndWords() {
        #expect(TerminalConnectFailure(ChannelError.connectTimeout(.seconds(15))) == .notAnswering)
        #expect(TerminalConnectFailure(IOError(errnoCode: EHOSTDOWN, reason: "connect")) == .notAnswering)
        #expect(TerminalConnectFailure(GlassTailscaleReach.Required(machine: "a", host: "100.64.0.1")) == .needsTailscale)
        #expect(TerminalConnectFailure(IOError(errnoCode: ECONNREFUSED, reason: "connect")) == .other)
        #expect(TerminalConnectFailure(SSHTransportError.authenticationFailed) == .other)

        let named = SSHConnection.userFacingMessage(for: ChannelError.connectTimeout(.seconds(15)), server: laptop)
        #expect(named == "studio at 192.0.2.10:22 didn't answer. It may be asleep, or off the network.")
        let unnamed = ServerConfiguration(name: "192.0.2.10", host: "192.0.2.10", username: "ann")
        #expect(SSHConnection.userFacingMessage(for: IOError(errnoCode: EHOSTUNREACH, reason: "connect"), server: unnamed)
                == "192.0.2.10:22 didn't answer. It may be asleep, or off the network.")
        #expect(SSHConnection.userFacingMessage(for: IOError(errnoCode: ECONNREFUSED, reason: "connect"), server: laptop)
                .contains("refused"), "a refused port is still a refused port")
    }

    @Test("Active, unable to list a machine, keeps no \"Detached\" for its down terminals, and says why")
    func activeForgetsWhatItCouldNotCheck() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        var machine = laptop
        machine.tmux = true
        let terminal = TerminalSession(server: machine)
        terminal.tmuxSessionName = "glass-3"
        manager.registerSession(terminal)
        terminal.state = .error("studio at 192.0.2.10:22 didn't answer. It may be asleep, or off the network.")
        terminal.tmuxWhileDown = .running(TerminalTmux.Session(name: "glass-3", attachedClients: 0, windows: 1, lastActivity: nil))
        #expect(GlassTerminalCapability.subtitle(for: [terminal]).contains("Detached"), "what the last listing said")

        let report = capability.runningReport(local: nil, hosts: [(machine, .skipped(TerminalListingSkip.notAnswering.reason))])
        #expect(terminal.tmuxWhileDown == nil)
        #expect(!GlassTerminalCapability.subtitle(for: [terminal]).contains("Detached"))
        #expect(report.unchecked.first?.reason == "Not checked: it didn't answer. It may be asleep, or off the network.")
        #expect(TerminalListingSkip.needsTailscale.reason.hasPrefix("Not checked: it's on your tailnet, and Tailscale is off on this "))
    }
}
