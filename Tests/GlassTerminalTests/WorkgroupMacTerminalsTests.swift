import Foundation
import Testing
@testable import GlassTerminal

/// 2026-10-29: a workgroup's Mac terminals belong to a Mac. The owner opened his Mac's workgroups on
/// the Vision Pro through stand-ins for "this Mac" over SSH, and each opening started new tmux
/// sessions in the home folder and ran the Mac's startup scripts there, beside the real ones —
/// once taking `glass-5` and `glass-6`, which another workgroup kept on the same Mac. Then: "We
/// haven't even touched 'multiple Macs' in this software yet."
///
/// Now the Mac that saves or runs a local terminal records itself on it, as its Terminal service in
/// the library (D86's link); every other device — another Mac too — opens it there over SSH on its
/// own session; one machine's tmux has one set of names, whichever way its terminals reach it; a
/// renamed session keeps its workgroups; and a relaunch never makes a session that ended.
///
/// No tmux runs here except where a test says so: hosts answer from memory, and nothing connects.
@MainActor
@Suite("A workgroup's Mac terminals belong to their Mac")
struct WorkgroupMacTerminalsTests {
    @MainActor private final class Writes {
        var lines: [String] = []
        func receive(_ data: Data) { lines.append(String(decoding: data, as: UTF8.self)) }
    }

    /// A host's tmux from memory, as `WorkgroupTmuxSessionsTests` has it, keeping each command.
    @MainActor private final class Host {
        var running: Set<String>
        private(set) var claims: [[String]] = []
        private(set) var commands: [String] = []
        init(running: Set<String> = []) { self.running = running }

        func answer(_ command: String) -> String {
            commands.append(command)
            // A tmux too old for control mode, so the attach line is the plain one.
            if command == TerminalTmux.versionCommand { return "tmux 3.1\n" }
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

    private func server(_ name: String) -> ServerConfiguration {
        var server = ServerConfiguration(name: name, host: "192.0.2.10", username: "ann")
        server.tmux = true
        return server
    }

    private func withSettings(_ body: (SettingsManager) async throws -> Void) async throws {
        let suite = "WorkgroupMacTerminals.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(SettingsManager(loadImmediately: false, settingsDefaults: defaults))
    }

    private func session(_ server: ServerConfiguration, host: Host, writes: Writes) -> TerminalSession {
        let session = TerminalSession(server: server, terminalWriteSink: { writes.receive($0) })
        session.tmuxCommandRunner = { host.answer($0) }
        return session
    }

    private func mac(_ mac: UUID?, tmux: String? = nil, folder: String? = "/srv/shop", command: String? = "./start.sh",
                     withoutTmux: Bool = false) -> LayoutPreset.SessionIntent {
        .init(kind: .local, label: "Shop", startupCommand: command, localDirectory: folder, tmuxSession: tmux,
              withoutTmux: withoutTmux, macServerID: mac)
    }

    // MARK: The record

    @Test("a Mac terminal records its Mac, which travels with it; an SSH terminal never has one, and older workgroups read")
    func record() throws {
        let bravo = UUID()
        let stamped = mac(bravo, tmux: "glass-7")
        let data = try JSONEncoder().encode(stamped)
        let read = try JSONDecoder().decode(LayoutPreset.SessionIntent.self, from: data)
        #expect(read.macServerID == bravo && read == stamped && read.isSupported)

        let older = try JSONDecoder().decode(LayoutPreset.SessionIntent.self,
                                             from: Data(#"{"schemaVersion":3,"kind":"local","restoration":"freshAuthorizedSession"}"#.utf8))
        #expect(older.macServerID == nil && older.isSupported, "a workgroup from before: no Mac yet")

        let sshJSON = #"{"schemaVersion":3,"kind":"ssh","serverID":"\#(UUID().uuidString)","restoration":"freshAuthorizedSession","macServerID":"\#(bravo.uuidString)"}"#
        #expect(try JSONDecoder().decode(LayoutPreset.SessionIntent.self, from: Data(sshJSON.utf8)).macServerID == nil)
        var forced = LayoutPreset.SessionIntent(serverID: UUID())
        forced.macServerID = bravo
        #expect(!forced.isSupported, "an SSH terminal with a Mac is not one this app writes")

        #expect(mac(nil).sameTerminal(as: stamped), "its Mac, found later, does not make it another terminal")
    }

    @Test("one machine, one set of names: a Mac's local terminals and SSH ones to it share them; an unclaimed one's are held everywhere")
    func oneMachineOneSetOfNames() {
        let bravo = UUID(), otherMac = UUID(), linux = UUID()
        let presets = [
            LayoutPreset(name: "Docs", sessionIntents: [mac(bravo, tmux: "glass-5"), mac(bravo, tmux: "glass-6")]),
            LayoutPreset(name: "Mixed", sessionIntents: [
                .init(serverID: bravo, tmuxSession: "glass-20"),
                .init(serverID: linux, tmuxSession: "glass-1"),
                mac(nil, tmux: "glass-9"),
                mac(otherMac, tmux: "glass-30")
            ])
        ]
        // The headset: no Mac of its own.
        #expect(LayoutPreset.tmuxSessionsHeld(in: presets, serverID: bravo) == ["glass-5", "glass-6", "glass-20", "glass-9"],
                "a new session on the Mac skips its own workgroups' names")
        #expect(LayoutPreset.tmuxSessionsHeld(in: presets, serverID: linux) == ["glass-1", "glass-9"])
        #expect(LayoutPreset.tmuxSessionsHeld(in: presets, serverID: otherMac) == ["glass-30", "glass-9"])
        // The Mac itself: its local terminals, and SSH ones to its own record, are its.
        #expect(LayoutPreset.tmuxSessionsHeld(in: presets, serverID: nil, thisMac: bravo) == ["glass-5", "glass-6", "glass-20", "glass-9"])
        #expect(LayoutPreset.tmuxSessionsHeld(in: presets, serverID: bravo, thisMac: bravo) == ["glass-5", "glass-6", "glass-20", "glass-9"])
        #expect(mac(bravo).machine(thisMac: bravo) == nil && mac(bravo).machine(thisMac: nil) == bravo)
        #expect(LayoutPreset.SessionIntent(serverID: bravo).machine(thisMac: bravo) == nil)
    }

    // MARK: Opening on its Mac from elsewhere

    @Test("on another device a Mac terminal opens on its Mac: its session joined and nothing typed; ended, made again in its folder with its command")
    func opensOnItsMac() async throws {
        try await withSettings { settings in
            let bravo = server("bravo")
            let preset = LayoutPreset(name: "Shop", sessionIntents: [mac(bravo.id, tmux: "glass-7")])
            settings.upsertLayoutPreset(preset)
            // A stand-in this device saved for it before is not used: it has its Mac now.
            let stale = WorkgroupSSHSubstitution(source: mac(nil, tmux: "glass-7"), serverID: bravo.id, directory: "", command: "./start.sh")
            let plan = LayoutRestorationPlan(preset: preset, availableServers: [bravo], substitutions: [0: stale.intent])
            let target = try #require(plan.targets.first)
            #expect(target.intent.kind == .ssh && target.intent.serverID == bravo.id)
            #expect(target.intent.tmuxSession == "glass-7" && target.folder == "/srv/shop" && target.sourceIndex == 0)
            #expect(LayoutRestorationPlan.mac(of: preset.sessionIntents[0], in: [bravo]) == bravo.id, "no stand-in asked for")
            #expect(LayoutRestorationPlan.mac(of: preset.sessionIntents[0], in: []) == nil, "a Mac this device doesn't know: the sheet")

            for running in [true, false] {
                let host = Host(running: running ? ["glass-7"] : [])
                let writes = Writes()
                let terminal = session(bravo, host: host, writes: writes)
                _ = terminal.installStartupCommand(target.intent.startupCommand)
                TerminalWorkgroupOpening.prepare(terminal, for: target, workgroupID: preset.id, settingsManager: settings)
                terminal.state = .connected
                await terminal.waitForTmuxAttach()
                await terminal.waitUntilTerminalWritesComplete()
                #expect(host.claims == [["glass-7"]])
                #expect(host.commands.first?.contains("-c '\\''/srv/shop'\\''") == true, "made in its folder: \(host.commands)")
                #expect(writes.lines == (running ? [Self.attach("glass-7")] : [Self.attach("glass-7"), "./start.sh\n"]),
                        running ? "running: joined, nothing typed into it" : "ended: made again, its command run once")
                terminal.disconnect()
            }
        }
    }

    @Test("a plain Mac terminal opens as a plain shell on its Mac, in its folder")
    func plainOnItsMac() throws {
        let bravo = server("bravo")
        let preset = LayoutPreset(name: "Shop", sessionIntents: [mac(bravo.id, withoutTmux: true)])
        let target = try #require(LayoutRestorationPlan(preset: preset, availableServers: [bravo]).targets.first)
        #expect(target.intent.withoutTmux && target.intent.tmuxSession == nil && target.folder == nil)
        #expect(target.intent.startupCommand == "cd -- '/srv/shop' && { ./start.sh; }")
    }

    @Test("a session claimed on its Mac goes back to the Mac terminal; a name for another machine never does")
    func claimedOnItsMacWritesBack() async throws {
        try await withSettings { settings in
            let bravo = server("bravo"), linux = server("linux")
            let preset = LayoutPreset(name: "Shop", sessionIntents: [mac(bravo.id)])
            settings.upsertLayoutPreset(preset)
            #expect(!settings.recordWorkgroupTmuxSession("glass-2", workgroupID: preset.id, index: 0,
                                                         opened: .init(serverID: linux.id)), "another machine's session")
            let target = try #require(LayoutRestorationPlan(preset: preset, availableServers: [bravo, linux]).targets.first)
            let host = Host(running: ["glass-1"])
            let terminal = session(bravo, host: host, writes: Writes())
            TerminalWorkgroupOpening.prepare(terminal, for: target, workgroupID: preset.id, settingsManager: settings)
            terminal.state = .connected
            await terminal.waitForTmuxAttach()
            #expect(terminal.tmuxSessionName == "glass-2")
            let saved = try #require(settings.layoutPresets.first?.sessionIntents.first)
            #expect(saved.kind == .local && saved.tmuxSession == "glass-2", "the Mac's tab opens on it next")
            terminal.disconnect()
        }
    }

    // MARK: Recording the Mac

    @Test("the Mac that runs or saves a workgroup's local terminal records itself; another Mac's stays theirs")
    func macRecordsItself() async throws {
        try await withSettings { settings in
            let bravo = UUID(), otherMac = UUID()
            let preset = LayoutPreset(name: "Shop", sessionIntents: [mac(nil, tmux: "glass-7"), mac(otherMac, tmux: "glass-8")])
            settings.upsertLayoutPreset(preset)
            #expect(!settings.recordWorkgroupMac(workgroupID: preset.id, index: 0, session: "glass-7"), "not a Mac the library knows")

            settings.thisMacServerID = { bravo }
            #expect(!settings.recordWorkgroupMac(workgroupID: preset.id, index: 0, session: "glass-3"), "the pane is another terminal now")
            #expect(settings.recordWorkgroupMac(workgroupID: preset.id, index: 0, session: "glass-7"))
            #expect(settings.layoutPresets.first?.sessionIntents.map(\.macServerID) == [bravo, otherMac])
            #expect(!settings.recordWorkgroupMac(workgroupID: preset.id, index: 1, session: "glass-8"), "another Mac's")

            #if os(macOS)
            // A workgroup this Mac saves: its local terminals no Mac has claimed are this Mac's.
            let saved = LayoutPreset(name: "New", sessionIntents: [mac(nil), .init(serverID: UUID())])
            settings.upsertLayoutPreset(saved)
            #expect(settings.layoutPresets.last?.sessionIntents.map(\.macServerID) == [bravo, nil])
            #endif
        }
    }

    // MARK: Renames

    @Test("a renamed session keeps its workgroups by its new name, on its own machine only")
    func renamesFollow() async throws {
        try await withSettings { settings in
            let bravo = UUID(), linux = UUID()
            let preset = LayoutPreset(name: "Mixed", sessionIntents: [
                mac(bravo, tmux: "glass-7"),
                .init(serverID: bravo, tmuxSession: "glass-7"),
                .init(serverID: linux, tmuxSession: "glass-7")
            ])
            settings.upsertLayoutPreset(preset)
            #expect(settings.renameWorkgroupTmuxSession(from: "glass-7", to: "shop", serverID: bravo))
            #expect(settings.layoutPresets.first?.sessionIntents.map(\.tmuxSession) == ["shop", "shop", "glass-7"])
            #expect(!settings.renameWorkgroupTmuxSession(from: "shop", to: "shop.v2", serverID: bravo), "a name tmux wouldn't take")

            // On the Mac itself, a local rename is its own machine's.
            settings.thisMacServerID = { bravo }
            #expect(settings.renameWorkgroupTmuxSession(from: "shop", to: "store", serverID: nil))
            #expect(settings.layoutPresets.first?.sessionIntents.map(\.tmuxSession) == ["store", "store", "glass-7"])
        }
    }

    // MARK: A relaunch never makes a session

    @Test("after a relaunch a terminal joins its session if it runs; if it ended, the terminal is gone and nothing is made")
    func relaunchJoinsOnly() async throws {
        try await withSettings { settings in
            let alpha = server("alpha")
            let target = LayoutRestorationTarget(intent: .init(serverID: alpha.id, startupCommand: "htop", tmuxSession: "glass-3"),
                                                 server: alpha, sourceIndex: nil)
            for running in [true, false] {
                let host = Host(running: running ? ["glass-3"] : [])
                let writes = Writes()
                let terminal = session(alpha, host: host, writes: writes)
                _ = terminal.installStartupCommand("htop")
                let closes = terminal.closeWindowNonce
                TerminalWorkgroupOpening.prepare(terminal, for: target, workgroupID: UUID(), settingsManager: settings, joinsOnly: true)
                terminal.state = .connected
                await terminal.waitForTmuxAttach()
                await terminal.waitUntilTerminalWritesComplete()
                #expect(host.claims.isEmpty, "never claimed, so never made")
                if running {
                    #expect(writes.lines == [Self.attach("glass-3")], "joined, nothing typed")
                    #expect(terminal.closeWindowNonce == closes)
                } else {
                    #expect(writes.lines.isEmpty, "no attach line, which would make it")
                    #expect(terminal.closeWindowNonce == closes &+ 1 && terminal.state == .disconnected, "gone, as an exit leaves it")
                }
                terminal.disconnect()
            }
        }
    }

    // MARK: A folder written with ~

    @Test("a folder written with ~ is the home of whoever runs the claim")
    func tildeFolder() {
        #expect(TerminalTmux.shellPath("~") == #""$HOME""#)
        #expect(TerminalTmux.shellPath("~/src/it's") == #""$HOME"/'src/it'\''s'"#)
        #expect(TerminalTmux.shellPath("/srv/shop") == "'/srv/shop'")
        #expect(TerminalTmux.shellPath("~ann/x") == "'~ann/x'", "another account's home is left as written")
        #expect(WorkgroupSSHSubstitution.startup("make", in: "~/app") == #"cd -- "$HOME"/'app' && { make; }"#)
    }

    @Test("a live claim starts its session in the folder it names, ~ as the home", .enabled(if: TerminalTmuxTests.tmux != nil))
    func liveFolder() throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("app"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appendingPathComponent("s").path
        let server = ["-S", socket, "-f", "/dev/null"]
        // The claim's home is the folder made here, so `~/app` is a folder that exists.
        let environment = ["PATH": "/usr/bin:/bin", "TMUX_TMPDIR": folder.path, "HOME": folder.path]
        defer { _ = TerminalTmuxTests.shell("\(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) kill-server", environment) }
        let script = TerminalTmux.claimScript(candidates: ["glass-1"], directory: "~/app", command: ["/bin/sleep", "600"],
                                              tmux: TerminalTmux.quoted(tmux), serverArguments: server)
        #expect(TerminalTmux.parseClaim(TerminalTmuxTests.shell(script, environment), candidates: ["glass-1"]) == .created("glass-1"))
        let path = TerminalTmuxTests.shell("\(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) display -p -t '=glass-1:' '#{pane_current_path}'",
                                           environment)
        #expect(URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath()
                == folder.appendingPathComponent("app").resolvingSymlinksInPath(), "\(path)")
    }
}
