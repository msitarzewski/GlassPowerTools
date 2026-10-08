import Foundation
import Testing
@testable import GlassTerminal

/// W4b (2026-10-08): workgroups keep their tmux sessions. A workgroup saves the session each
/// terminal is in, opening it claims that name — joined while it runs, made again (and only then
/// its startup command) once it has ended — a terminal without one writes back the one it claims,
/// once, and a phone connects only the terminal it shows.
///
/// No tmux runs here: hosts answer from memory, and nothing connects.
@MainActor
@Suite("Workgroups keep their tmux sessions")
struct WorkgroupTmuxSessionsTests {
    @MainActor private final class Writes {
        var lines: [String] = []
        func receive(_ data: Data) { lines.append(String(decoding: data, as: UTF8.self)) }
    }

    /// A host's tmux from memory: the list says what runs, and a claim makes the first name it
    /// offers that is not running, or answers `exists` for the one name asked for.
    @MainActor private final class Host {
        var running: Set<String>
        private(set) var claims: [[String]] = []
        init(running: Set<String> = []) { self.running = running }

        func answer(_ command: String) -> String {
            guard let offered = TerminalTmuxTests.offered(in: command) else {
                return running.sorted().map { "\($0)\t0\t1\t0" }.joined(separator: "\n")
            }
            claims.append(offered)
            for name in offered {
                if !running.contains(name) {
                    running.insert(name)
                    return "created \(name)\n"
                }
                if offered.count == 1 { return "exists \(name)\n" }
            }
            return "__glass_tmux_failed__\n"
        }
    }

    private static func attach(_ name: String) -> String {
        " command -v tmux >/dev/null && exec tmux -u new-session -A -s '\(name)'\n"
    }

    private func server(_ name: String = "alpha", tmux: Bool? = true) -> ServerConfiguration {
        var server = ServerConfiguration(name: name, host: "192.0.2.10", username: "ann")
        server.tmux = tmux
        return server
    }

    private func withSettings(_ body: (SettingsManager, UserDefaults) async throws -> Void) async throws {
        let suite = "WorkgroupTmuxSessions.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(SettingsManager(loadImmediately: false, settingsDefaults: defaults), defaults)
    }

    private func session(_ server: ServerConfiguration, host: Host, writes: Writes) -> TerminalSession {
        let session = TerminalSession(server: server, terminalWriteSink: { writes.receive($0) })
        session.tmuxCommandRunner = { host.answer($0) }
        return session
    }

    @Test("a workgroup's tmux session is saved, read back, and old workgroups without one still read")
    func intentCoding() throws {
        let serverID = UUID()
        let ssh = LayoutPreset.SessionIntent(serverID: serverID, label: "Logs", tmuxSession: "glass-3")
        let local = LayoutPreset.SessionIntent(kind: .local, startupCommand: "make", tmuxSession: "work")
        for intent in [ssh, local] {
            let decoded = try JSONDecoder().decode(LayoutPreset.SessionIntent.self, from: JSONEncoder().encode(intent))
            #expect(decoded == intent && decoded.isSupported)
        }
        #expect(try JSONDecoder().decode(LayoutPreset.SessionIntent.self, from: JSONEncoder().encode(ssh)).tmuxSession == "glass-3")

        // Names tmux would not take are read as none, as an unreadable label is: the workgroup
        // still opens, and the terminal claims a new session.
        for bad in ["glass:1", "a.b", "-t", "", "tab\tname"] {
            #expect(LayoutPreset.SessionIntent(serverID: serverID, tmuxSession: bad).tmuxSession == nil)
            var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(ssh)) as? [String: Any])
            object["tmuxSession"] = bad
            let decoded = try JSONDecoder().decode(LayoutPreset.SessionIntent.self,
                                                   from: JSONSerialization.data(withJSONObject: object))
            #expect(decoded.tmuxSession == nil && decoded.isSupported, "\(bad)")
        }
        var set = ssh
        set.tmuxSession = "glass:1"
        #expect(!set.isSupported, "an invalid name put there directly is refused, as an invalid label is")

        // Saved before W4b: no key, the same schema, and nothing written for a terminal without one.
        var old = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(ssh)) as? [String: Any])
        old.removeValue(forKey: "tmuxSession")
        let decodedOld = try JSONDecoder().decode(LayoutPreset.SessionIntent.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decodedOld.tmuxSession == nil && decodedOld.isSupported && decodedOld.schemaVersion == 3)
        let none = String(decoding: try JSONEncoder().encode(LayoutPreset.SessionIntent(serverID: serverID)), as: UTF8.self)
        #expect(!none.contains("tmuxSession"))

        let preset = LayoutPreset(name: "Ops", sessionIntents: [ssh, local])
        let decodedPreset = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(preset))
        #expect(decodedPreset.sessionIntents.map(\.tmuxSession) == ["glass-3", "work"])
        #expect(decodedPreset.isValidForPersistence && !decodedPreset.needsMigration)
    }

    @Test("the editor keeps a tab's session; another server or kind of terminal leaves it behind")
    func editorDraft() {
        let alpha = UUID(), beta = UUID()
        let draft = WorkgroupTabDraft(intent: .init(serverID: alpha, label: "Logs", tmuxSession: "glass-3"))
        #expect(draft.intent.tmuxSession == "glass-3", "rebuilt from the draft, the name survives an edit")

        var edited = draft
        edited.label = "Tail"
        edited.startupCommand = "htop"
        edited.serverID = alpha
        #expect(edited.intent.tmuxSession == "glass-3")

        var moved = draft
        moved.serverID = beta
        #expect(moved.intent.tmuxSession == nil, "a session lives on its host")
        var local = draft
        local.kind = .local
        #expect(local.intent.tmuxSession == nil)

        let saved = [LayoutPreset(name: "Desk", serverIDs: [alpha])]
        #expect(WorkgroupEditorView.workgroup(named: "desk", in: saved)?.id == saved[0].id,
                "a window saved under its workgroup's name offers to replace it")
        #expect(WorkgroupEditorView.workgroup(named: "Desk 2", in: saved) == nil)

        let named = LayoutPreset(name: "Ops", sessionIntents: [draft.intent])
        #expect(WorkgroupEditorContext.edit(named).sessionIntents.map(\.tmuxSession) == ["glass-3"])
        #expect(WorkgroupEditorContext.duplicate(named).sessionIntents.map(\.tmuxSession) == [nil],
                "a copy opens terminals of its own")
    }

    @Test("opening a workgroup claims its saved session: running, only the attach line; ended, the attach line then the command")
    func claimsSavedName() async throws {
        try await withSettings { settings, _ in
            let server = server()
            let preset = LayoutPreset(name: "Ops", sessionIntents: [.init(serverID: server.id, startupCommand: "htop",
                                                                         tmuxSession: "glass-3")])
            settings.upsertLayoutPreset(preset)
            let target = try #require(LayoutRestorationPlan(preset: preset, availableServers: [server]).targets.first)

            for (running, expected) in [(true, [Self.attach("glass-3")]), (false, [Self.attach("glass-3"), "htop\n"])] {
                let host = Host(running: running ? ["glass-3"] : [])
                let writes = Writes()
                let terminal = session(server, host: host, writes: writes)
                _ = terminal.installStartupCommand(target.intent.startupCommand)
                TerminalWorkgroupOpening.prepare(terminal, for: target, workgroupID: preset.id, settingsManager: settings)
                terminal.state = .connected
                await terminal.waitForTmuxAttach()
                await terminal.waitUntilTerminalWritesComplete()
                #expect(host.claims == [["glass-3"]], "claimed, not listed and numbered")
                #expect(writes.lines == expected, running ? "exists: joined, nothing typed into it" : "created: the command runs in it")
                terminal.disconnect()
            }
            #expect(settings.layoutPresets.first?.sessionIntents.first?.tmuxSession == "glass-3")
        }
    }

    @Test("a terminal without a saved session writes the one it claims back to its workgroup, once")
    func writesBackOnce() async throws {
        try await withSettings { settings, _ in
            let server = server()
            let preset = LayoutPreset(name: "Ops", sessionIntents: [
                .init(serverID: server.id, tmuxSession: "glass-1"),
                .init(serverID: server.id, startupCommand: "htop")
            ])
            settings.upsertLayoutPreset(preset)
            let before = try #require(settings.layoutPresets.first?.modifiedAt)
            let target = LayoutRestorationPlan(preset: preset, availableServers: [server]).targets[1]
            #expect(target.sourceIndex == 1)
            let host = Host(running: ["glass-1"])

            let writes = Writes()
            let first = session(server, host: host, writes: writes)
            _ = first.installStartupCommand("htop")
            TerminalWorkgroupOpening.prepare(first, for: target, workgroupID: preset.id, settingsManager: settings)
            try await Task.sleep(for: .milliseconds(5))
            first.state = .connected
            await first.waitForTmuxAttach()
            await first.waitUntilTerminalWritesComplete()
            #expect(first.tmuxSessionName == "glass-2")
            #expect(writes.lines == [Self.attach("glass-2"), "htop\n"], "new: the command runs in it")
            let saved = try #require(settings.layoutPresets.first)
            #expect(saved.sessionIntents.map(\.tmuxSession) == ["glass-1", "glass-2"], "written back to its own pane")
            #expect((saved.modifiedAt ?? .distantPast) > before, "a change, so it travels")

            // Reconnecting attaches to it again: nothing more is claimed or written.
            first.state = .reconnecting
            first.state = .connected
            await first.waitForTmuxAttach()
            #expect(host.claims.count == 1)

            // Opened again from the same old copy — another device, before the name arrived —
            // it claims its own, and the name already saved is not replaced.
            let second = session(server, host: host, writes: Writes())
            TerminalWorkgroupOpening.prepare(second, for: target, workgroupID: preset.id, settingsManager: settings)
            second.state = .connected
            await second.waitForTmuxAttach()
            #expect(second.tmuxSessionName == "glass-3")
            #expect(settings.layoutPresets.first?.sessionIntents.map(\.tmuxSession) == ["glass-1", "glass-2"])

            // A device's stand-in for a Mac terminal is not the workgroup's, and keeps nothing.
            var standIn = target
            standIn.sourceIndex = nil
            let third = session(server, host: host, writes: Writes())
            TerminalWorkgroupOpening.prepare(third, for: standIn, workgroupID: preset.id, settingsManager: settings)
            #expect(third.tmuxSessionClaimed == nil)
            for terminal in [first, second, third] { terminal.disconnect() }
        }
    }

    @Test("a new terminal never takes a session a saved workgroup holds on that server")
    func newNamesSkipHeld() async throws {
        try await withSettings { settings, defaults in
            let alpha = server("alpha"), beta = server("beta")
            settings.upsertLayoutPreset(LayoutPreset(name: "Ops", sessionIntents: [
                .init(serverID: alpha.id, tmuxSession: "glass-1"),
                .init(serverID: alpha.id, tmuxSession: "glass-3"),
                .init(serverID: beta.id, tmuxSession: "glass-2"),
                .init(kind: .local, tmuxSession: "glass-4")
            ]))
            #expect(settings.tmuxSessionsHeld(forServer: alpha.id) == ["glass-1", "glass-3"], "this server's, not another machine's")

            let servers = ServerManager(loadImmediately: false, defaults: defaults,
                                        passwordStore: ServerPasswordStore(retrieve: { _ in "unused" }, save: { _, _ in }, delete: { _ in }))
            servers.servers = [alpha, beta]
            let manager = SessionManager(serverManager: servers, loadImmediately: false)
            let host = Host()
            let terminal = try manager.createSessionWithoutConnecting(serverID: alpha.id, settingsManager: settings)
            defer { manager.closeSession(terminal) }
            terminal.tmuxCommandRunner = { host.answer($0) }
            terminal.state = .connected
            await terminal.waitForTmuxAttach()
            #expect(Array(host.claims.first?.prefix(2) ?? []) == ["glass-2", "glass-4"], "glass-1 and glass-3 are the workgroup's")
            #expect(terminal.tmuxSessionName == "glass-2")
        }
    }

    @Test("on iPhone a workgroup makes a slot per terminal and connects only the one shown")
    func iPhoneConnectsOnlyTheShownSlot() async throws {
        final class RecordingManager: SessionManager {
            var asked: [UUID] = []
            override func connectWhenShown(_ session: TerminalSession, settingsManager: SettingsManager) async throws {
                asked.append(session.id)
                session.state = .connecting
            }
        }
        try await withSettings { settings, defaults in
            let alpha = server("alpha", tmux: nil), beta = server("beta", tmux: nil)
            let servers = ServerManager(loadImmediately: false, defaults: defaults,
                                        passwordStore: ServerPasswordStore(retrieve: { _ in "unused" }, save: { _, _ in }, delete: { _ in }))
            servers.servers = [alpha, beta]
            let manager = RecordingManager(serverManager: servers, loadImmediately: false)
            let preset = LayoutPreset(name: "Phone", sessionIntents: [
                .init(serverID: alpha.id, label: "Logs"),
                .init(serverID: alpha.id),
                .init(serverID: beta.id, startupCommand: "htop", tmuxSession: "work")
            ])
            let plan = LayoutRestorationPlan(preset: preset, availableServers: [alpha, beta])
            manager.createWorkgroup(id: preset.id, name: preset.name, colorTag: preset.colorTag)
            #expect(TerminalWorkgroupOpening.makeSlots(for: plan, workgroupID: preset.id,
                                                       sessionManager: manager, settingsManager: settings).isEmpty)
            let slots = manager.sessions(inWorkgroup: preset.id)
            defer { manager.closeWorkgroup(preset.id) }
            #expect(slots.map(\.server.id) == [alpha.id, alpha.id, beta.id], "one slot per terminal, in order")
            #expect(slots.allSatisfy { $0.state == .disconnected }, "made, none connected")
            #expect(manager.selectedSession(inWorkgroup: preset.id)?.id == slots[0].id)
            #expect(slots[2].tmuxSessionName == "work" && slots[2].tmuxClaimsGivenName && slots[2].hasPendingStartupCommand)
            #expect(TerminalWorkgroupOpening.isOpen(preset.id, in: manager), "open here: opening it again shows it")

            try await TerminalWorkgroupOpening.connectShownSlot(in: preset.id, sessionManager: manager, settingsManager: settings)
            #expect(manager.asked == [slots[0].id], "only the slot shown")
            #expect(slots.map(\.connectsWhenShown) == [false, true, true])

            manager.selectSession(slots[2].id, inWorkgroup: preset.id)
            try await TerminalWorkgroupOpening.connectShownSlot(in: preset.id, sessionManager: manager, settingsManager: settings)
            #expect(manager.asked == [slots[0].id, slots[2].id], "choosing a slot connects it")
            manager.selectSession(slots[0].id, inWorkgroup: preset.id)
            try await TerminalWorkgroupOpening.connectShownSlot(in: preset.id, sessionManager: manager, settingsManager: settings)
            #expect(manager.asked == [slots[0].id, slots[2].id], "one already on its way is left to finish")

            #expect(TerminalWorkgroupOpening.slotTitle(slots[0], position: 0) == "Logs")
            #expect(TerminalWorkgroupOpening.slotTitle(slots[1], position: 1) == "Terminal 2 · alpha")

            // A terminal added another way — "+" — is not a slot: shown, it is not connected
            // for it, and it reconnects on its own as before.
            let added = TerminalSession(server: alpha)
            manager.registerSession(added)
            #expect(manager.appendSession(added, toWorkgroup: preset.id))
            added.state = .error("Connection failed")
            try await TerminalWorkgroupOpening.connectShownSlot(in: preset.id, sessionManager: manager, settingsManager: settings)
            #expect(manager.asked == [slots[0].id, slots[2].id] && !added.connectsWhenShown)
            #expect(slots[0].connectsWhenShown && slots[2].connectsWhenShown, "the slots are hidden now")
            manager.selectSession(slots[0].id, inWorkgroup: preset.id)
            try await TerminalWorkgroupOpening.connectShownSlot(in: preset.id, sessionManager: manager, settingsManager: settings)

            // Back from suspension: the hidden slot's lost connection waits to be shown; the one
            // on screen reconnects as before.
            slots[1].state = .error("Connection lost")
            slots[1].attemptAutoReconnect(autoReconnectEnabled: true)
            #expect(slots[1].state == .error("Connection lost") && slots[1].connectsOnShow)
            slots[0].state = .error("Connection lost")
            slots[0].attemptAutoReconnect(autoReconnectEnabled: true)
            #expect(slots[0].state == .reconnecting)
            slots[0].cancelReconnect()
        }
    }

    @Test("a device's stand-ins for Mac terminals keep the others in place, and survive a name the Mac wrote back")
    func standIns() async throws {
        try await withSettings { settings, _ in
            let alpha = server()
            let local = LayoutPreset.SessionIntent(kind: .local, label: "Build", localDirectory: "/tmp")
            var preset = LayoutPreset(name: "Mixed", sessionIntents: [local, .init(serverID: alpha.id, tmuxSession: "glass-5")])
            let standIn = WorkgroupSSHSubstitution(source: local, serverID: alpha.id, directory: "/srv", command: "")
            settings.saveSSHSubstitutions([0: standIn], for: preset)

            let plan = LayoutRestorationPlan(preset: preset, availableServers: [alpha], substitutions: [0: standIn.intent])
            #expect(plan.targets.map(\.sourceIndex) == [nil, 1], "the stand-in is not the workgroup's; the other keeps its place")
            #expect(plan.targets.map(\.intent.tmuxSession) == [nil, "glass-5"])
            #expect(LayoutRestorationPlan(preset: preset, availableServers: [alpha], substitutions: [:]).targets.map(\.sourceIndex) == [1],
                    "a Mac terminal left without one is skipped")

            preset.sessionIntents[0].tmuxSession = "glass-6"
            #expect(settings.sshSubstitutions(for: preset)[0] == standIn, "the Mac's name does not undo this device's choice")
        }
    }
}
