import Foundation
import Testing
import GlassLayers
import GlassConnectionKit
import GlassShell
@testable import GlassTerminal

/// W13 (owner, 2026-10-09): running sessions chosen in Active open together, in one new window.
/// On iPad and Vision Pro that is one workgroup window holding a terminal per session; on iPhone
/// the same workgroup opens as slots, and only the one shown connects (W4b).
///
/// No tmux runs and nothing connects: hosts answer from memory, and connecting is recorded.
@MainActor
@Suite("Running sessions open together")
struct TerminalOpenTogetherTests {
    private func server(_ name: String, legacy: Bool = false) -> ServerConfiguration {
        var server = ServerConfiguration(name: name, host: "\(name).example.com", username: "ann")
        server.tmux = true
        if legacy { server.allowLegacyAlgorithms = true }
        return server
    }

    private func withSettings(_ body: (SettingsManager, UserDefaults) async throws -> Void) async throws {
        let suite = "TerminalOpenTogether.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(SettingsManager(loadImmediately: false, settingsDefaults: defaults), defaults)
    }

    private func listed(_ name: String, attached: Int = 0) -> TerminalTmux.Session {
        TerminalTmux.Session(name: name, attachedClients: attached, windows: 1)
    }

    @Test("each running row carries what to attach to, and Open together is one request, in order")
    func rowsCarryTheirAttachment() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let alpha = server("alpha"), bravo = server("bravo")
        runtime.sessionManager.serverManager.servers = [alpha, bravo]
        let rows = capability.runningReport(local: nil, hosts: [
            (alpha, .sessions([listed("glass-1"), listed("glass-3", attached: 1)])),
            (bravo, .sessions([listed("logs")])),
        ]).sessions
        #expect(rows.map(\.attachment) == [
            GlassRunningAttachment(kind: .ssh, endpointID: EndpointID(rawValue: alpha.id), name: "glass-1"),
            GlassRunningAttachment(kind: .ssh, endpointID: EndpointID(rawValue: alpha.id), name: "glass-3"),
            GlassRunningAttachment(kind: .ssh, endpointID: EndpointID(rawValue: bravo.id), name: "logs"),
        ])
        try #require(rows.count == 3)

        _ = runtime.takeRequests()
        capability.openRunningSessions([rows[2], rows[0], rows[1]].compactMap(\.attachment))
        let requests = runtime.takeRequests()
        #expect(requests.count == 1, "one request for all of them, never one per row")
        guard case .openTmuxSessions(let targets)? = requests.first else {
            Issue.record("Open together asks for the sessions together")
            return
        }
        #expect(targets == [TerminalTmuxTarget(serverID: bravo.id, name: "logs"),
                            TerminalTmuxTarget(serverID: alpha.id, name: "glass-1"),
                            TerminalTmuxTarget(serverID: alpha.id, name: "glass-3")], "in the order given")

        // Anything else's, or a name tmux would not take, is not the terminal's to open.
        capability.openRunningSessions([GlassRunningAttachment(kind: .database, endpointID: EndpointID(), name: "x"),
                                        GlassRunningAttachment(kind: .ssh, endpointID: EndpointID(rawValue: alpha.id), name: "a:b")])
        #expect(runtime.takeRequests().isEmpty)
    }

    /// Active's Open as Tab In (the owner, 2026-10-15): "show existing tab groups. So I can open a
    /// new session into a group."
    @Test("Open as Tab In: the windows with room, by Active's names, newest first; one request for the window chosen")
    func openAsTabIn() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let alpha = server("alpha")
        manager.serverManager.servers = [alpha]
        func window(_ name: String, terminals: Int) -> UUID {
            let group = manager.createWorkgroup(name: name, colorTag: .blue)
            for _ in 0..<terminals {
                let session = TerminalSession(server: alpha)
                manager.registerSession(session)
                session.state = .connected
                _ = manager.appendSession(session, toWorkgroup: group)
            }
            return group
        }
        let backend = window("Backend", terminals: 1)
        let full = window("Full", terminals: LayoutPreset.maximumSessionCount)
        let empty = manager.createWorkgroup(name: "Empty", colorTag: .blue)
        let logs = window("Logs", terminals: 2)

        let groups = GlassTerminalCapability.workgroupTabGroups(manager)
        #expect(groups.map(\.title) == ["Logs", "Backend"], "newest first; a full window and one with nothing live are left out")
        #expect(groups.map(\.id) == [logs, backend].map(\.uuidString))

        _ = runtime.takeRequests()
        let attachment = GlassTerminalCapability.attachment(serverID: alpha.id, name: "glass-2")
        capability.openRunningSessions([attachment], inTabGroup: backend.uuidString)
        let requests = runtime.takeRequests()
        #expect(requests.count == 1)
        guard case .addTmuxSessions(let targets, let windowID)? = requests.first else {
            Issue.record("Open as Tab In asks for the window: \(requests)")
            return
        }
        #expect(targets == [TerminalTmuxTarget(serverID: alpha.id, name: "glass-2")])
        #expect(windowID == backend)
        for group in [backend, full, empty, logs] { manager.closeWorkgroup(group) }
    }

    @Test("Open as Tab In: a window takes what it has room for and says what didn't open")
    func roomInTheWindow() {
        let alpha = server("alpha")
        let targets = ["one", "two", "three"].map { TerminalTmuxTarget(serverID: alpha.id, name: $0) }
        let plan = TerminalOpenTogether.plan(targets, servers: [alpha], room: 1)
        #expect(plan.opening == [targets[0]])
        #expect(plan.notOpened == ["That window has room for 1 more, so the other 2 didn't open."])
        #expect(TerminalOpenTogether.plan(targets, servers: [alpha], room: 0).notOpened == ["That window is full, so they didn't open."])
        #expect(TerminalOpenTogether.plan(targets, servers: [alpha], room: 5).opening == targets)
    }

    @Test("on iPad and Vision Pro: one workgroup, a terminal per session in order, each claiming its own; never saved")
    func oneWorkgroupForThree() async throws {
        try await withSettings { settings, _ in
            let alpha = server("alpha"), bravo = server("bravo")
            let targets = [TerminalTmuxTarget(serverID: alpha.id, name: "glass-1"),
                           TerminalTmuxTarget(serverID: bravo.id, name: "logs"),
                           TerminalTmuxTarget(serverID: alpha.id, name: "glass-3")]
            let plan = TerminalOpenTogether.plan(targets, servers: [alpha, bravo])
            #expect(plan.opening == targets && plan.notOpened.isEmpty)

            let preset = try #require(TerminalOpenTogether.workgroup(for: plan.opening, servers: [alpha, bravo]))
            #expect(preset.name == "alpha, bravo", "named for the machines it is on")
            #expect(preset.sessionIntents.map(\.serverID) == [alpha.id, bravo.id, alpha.id])
            #expect(preset.sessionIntents.map(\.tmuxSession) == ["glass-1", "logs", "glass-3"])
            #expect(!TerminalConnectFlow.workgroupNeedsLegacyConsent(preset, servers: [alpha, bravo]))

            let restoration = LayoutRestorationPlan(preset: preset, availableServers: [alpha, bravo])
            #expect(restoration.failures.isEmpty && restoration.targets.map(\.server?.id) == [alpha.id, bravo.id, alpha.id])
            for (target, name) in zip(restoration.targets, ["glass-1", "logs", "glass-3"]) {
                let terminal = TerminalSession(server: try #require(target.server))
                TerminalWorkgroupOpening.prepare(terminal, for: target, workgroupID: preset.id, settingsManager: settings)
                #expect(terminal.tmuxSessionName == name && terminal.tmuxClaimsGivenName,
                        "joins its session while it runs; made again if it has ended")
                #expect(terminal.tmuxSessionClaimed == nil, "and writes nothing back to a workgroup that isn't saved")
            }
        }
    }

    @Test("on iPhone the same workgroup opens as slots, one per session, in order, none connected")
    func iPhoneOpensItAsSlots() async throws {
        try await withSettings { settings, defaults in
            let alpha = server("alpha"), bravo = server("bravo")
            let servers = ServerManager(loadImmediately: false, defaults: defaults,
                                        passwordStore: ServerPasswordStore(retrieve: { _ in "unused" }, save: { _, _ in }, delete: { _ in }))
            servers.servers = [alpha, bravo]
            let manager = SessionManager(serverManager: servers, loadImmediately: false)
            let targets = [TerminalTmuxTarget(serverID: alpha.id, name: "glass-1"),
                           TerminalTmuxTarget(serverID: bravo.id, name: "logs"),
                           TerminalTmuxTarget(serverID: alpha.id, name: "glass-3")]
            let preset = try #require(TerminalOpenTogether.workgroup(for: TerminalOpenTogether.plan(targets, servers: [alpha, bravo]).opening,
                                                                     servers: [alpha, bravo]))
            // As `openVisionWorkgroup` opens it on a phone.
            let workgroupID = manager.createWorkgroup(id: preset.id, name: preset.name, colorTag: preset.colorTag)
            let plan = LayoutRestorationPlan(preset: preset, availableServers: [alpha, bravo])
            #expect(TerminalWorkgroupOpening.makeSlots(for: plan, workgroupID: workgroupID,
                                                       sessionManager: manager, settingsManager: settings).isEmpty)
            defer { manager.closeWorkgroup(workgroupID) }
            let slots = manager.sessions(inWorkgroup: workgroupID)
            #expect(slots.map(\.server.id) == [alpha.id, bravo.id, alpha.id], "one workgroup, a slot per session, in order")
            try #require(slots.count == 3)
            #expect(slots.map(\.tmuxSessionName) == ["glass-1", "logs", "glass-3"])
            #expect(slots.allSatisfy { $0.state == .disconnected }, "made, none connected")
            // That only the one shown then connects is WorkgroupTmuxSessionsTests' to say.
        }
    }

    @Test("a session that can't open with the others is left out, in plain words; the rest still open")
    func leftOutInPlainWords() {
        let alpha = server("alpha"), old = server("oldbox", legacy: true)
        let gone = UUID()
        let targets = [TerminalTmuxTarget(serverID: alpha.id, name: "glass-1"),
                       TerminalTmuxTarget(serverID: old.id, name: "glass-2"),
                       TerminalTmuxTarget(serverID: gone, name: "glass-4"),
                       TerminalTmuxTarget(serverID: alpha.id, name: "glass-5")]
        let plan = TerminalOpenTogether.plan(targets, servers: [alpha, old])
        #expect(plan.opening.map(\.name) == ["glass-1", "glass-5"])
        #expect(plan.notOpened == [
            "oldbox uses legacy algorithms, so glass-2 didn't open with the others. Open it on its own to review its security settings.",
            "glass-4 didn't open: its machine's Terminal service is no longer here.",
        ], "legacy algorithms need their own confirmation, which a window of several never asks")
        let preset = TerminalOpenTogether.workgroup(for: plan.opening, servers: [alpha, old])
        #expect(preset.map { !TerminalConnectFlow.workgroupNeedsLegacyConsent($0, servers: [alpha, old]) } == true,
                "so the workgroup opens rather than refusing every session")
        #expect(TerminalOpenTogether.workgroup(for: [], servers: [alpha]) == nil)
    }
}
