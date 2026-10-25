//
//  LiveTmuxTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  D44 against a real host: the exact lines Glass sends, through a real PTY shell and exec channel.
//  Gated like the other live tests (NOT RUN when unconfigured). Without tmux on the host it checks
//  the missing-tmux answer and that the attach line leaves an ordinary shell; with tmux it creates,
//  leaves, reattaches to and ends a session of its own, and touches no other session.
//

import Foundation
import Testing
import SwiftTerm
import GlassSSHTransport
@testable import GlassTerminal
@testable import GlassTerminalEmulator

@Suite("tmux against a real host (gated)", .serialized, .enabled(if: LiveRemoteEnvironment.isConfigured, "no test host: set GPT_SSH_TEST_HOST, GPT_SSH_TEST_USER and GPT_SSH_TEST_KEY_PATH or GPT_SSH_TEST_PASSWORD"))
struct LiveTmuxTests {
    private func transport() async throws -> SSHTransport? {
        guard LiveRemoteEnvironment.isConfigured else {
            print("NOT RUN: set GPT_SSH_TEST_HOST, GPT_SSH_TEST_USER and GPT_SSH_TEST_KEY_PATH")
            return nil
        }
        let endpoint = SSHEndpoint(host: LiveRemoteEnvironment.host!, port: LiveRemoteEnvironment.port,
                                   username: LiveRemoteEnvironment.user!)
        let hop = SSHHop(displayName: "live tmux test", endpoint: endpoint, credential: .custom("integration"),
                         options: SSHConnectionOptions(keepAliveInterval: 15))
        let transport = SSHTransport(route: SSHRoute(target: hop), credentials: LiveCredentialResolver(),
                                     trustStore: InMemoryHostTrustStore(), trustDecider: TrustThisRun())
        try await transport.connect()
        return transport
    }

    private func sessions(_ transport: SSHTransport) async throws -> TerminalTmux.Listing {
        TerminalTmux.parse(try await transport.execute(TerminalTmux.listCommand))
    }

    /// Polls the host's list until `condition` holds, for up to five seconds.
    private func waitFor(_ transport: SSHTransport, _ condition: ([TerminalTmux.Session]) -> Bool) async throws -> Bool {
        for _ in 0..<50 {
            if case .sessions(let list) = try await sessions(transport), condition(list) { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @Test func attachLeaveReattachEnd() async throws {
        guard let transport = try await transport() else { return }
        defer { Task { await transport.close() } }
        let name = "gpt-live-\(UUID().uuidString.prefix(8))"
        let attach = TerminalTmux.attachLine(name: name, takeOver: false)

        guard case .sessions = try await sessions(transport) else {
            // No tmux: the line Glass types must leave an ordinary, working shell.
            print("tmux is not installed on the test host: checking the missing-tmux path only")
            let shell = try await transport.openShell(pty: SSHPTYRequest(columns: 100, rows: 30))
            try await shell.sendCommand(attach)
            try await shell.sendCommand("echo still-a-shell-$((6*7))")
            try await shell.sendCommand("exit")
            var collected = Data()
            for await chunk in shell.output { if case .stdout(let data) = chunk { collected.append(data) } }
            #expect(String(decoding: collected, as: UTF8.self).contains("still-a-shell-42"))
            return
        }

        // Create: the typed line starts the session, attached.
        let first = try await transport.openShell(pty: SSHPTYRequest(columns: 100, rows: 30))
        try await first.sendCommand(attach)
        #expect(try await waitFor(transport) { $0.contains { $0.name == name && $0.attachedClients == 1 } })

        // Where the shell is: tmux keeps OSC 7 to itself, so Glass asks tmux (the AI assistant
        // and Open Folder Here).
        try await first.sendCommand("cd /tmp")
        var path = ""
        for _ in 0..<50 where path != "/tmp" {
            path = try await transport.execute(TerminalTmux.currentPathCommand(name: name)).trimmingCharacters(in: .whitespacesAndNewlines)
            if path != "/tmp" { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(path == "/tmp")

        // Leave: the client goes, the session stays — what Active lists as Detached.
        await first.close()
        #expect(try await waitFor(transport) { $0.contains { $0.name == name && $0.attachedClients == 0 } })

        // Reattach: the same line attaches rather than creating a second session.
        let second = try await transport.openShell(pty: SSHPTYRequest(columns: 100, rows: 30))
        try await second.sendCommand(attach)
        #expect(try await waitFor(transport) { $0.filter { $0.name == name }.count == 1 && $0.contains { $0.name == name && $0.attachedClients == 1 } })

        // End: gone from the host, and the attached shell ends with it.
        _ = try await transport.execute(TerminalTmux.killCommand(name: name))
        #expect(try await waitFor(transport) { !$0.contains { $0.name == name } })
        await second.close()
    }

    /// W4a (2026-10-08): a new terminal's session is made by a claim over the exec channel, not by
    /// the line typed into its shell. When that claim starts the host's tmux server, the server
    /// takes the exec channel's environment. Two private servers (`-L`), each started one way;
    /// the shell inside each writes what it sees, and the two should agree.
    @Test func claimedSessionSeesWhatATypedOneSees() async throws {
        guard let transport = try await transport() else { return }
        defer { Task { await transport.close() } }
        guard case .sessions = try await sessions(transport) else {
            Issue.record("the test host has no tmux; these tests need it")
            return
        }
        let id = UUID().uuidString.prefix(8).lowercased()
        let claimed = "gpt-claim-\(id)", typed = "gpt-typed-\(id)"
        func run(_ script: String) async throws -> String {
            try await transport.execute("sh -c " + TerminalTmux.quoted(#"PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; "# + script + "; exit 0"))
        }
        func tmux(_ label: String) -> String { "tmux -u -L \(label)" }

        let claim = try await run(TerminalTmux.claimScript(candidates: ["glass-1"], tmux: "tmux", serverArguments: ["-L", claimed]))
        #expect(TerminalTmux.parseClaim(claim, candidates: ["glass-1"]) == .created("glass-1"))
        let shell = try await transport.openShell(pty: SSHPTYRequest(columns: 100, rows: 30))
        try await shell.sendCommand(" command -v tmux >/dev/null && exec \(tmux(typed)) new-session -A -s glass-1")
        for _ in 0..<50 {
            if try await run("\(tmux(typed)) has-session -t '=glass-1' 2>/dev/null && echo up") == "up\n" { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        var seen: [String: String] = [:]
        for label in [claimed, typed] {
            let file = "/tmp/\(label).env"
            _ = try await run("\(tmux(label)) send-keys -t '=glass-1:' -l 'env > \(file)' && \(tmux(label)) send-keys -t '=glass-1:' Enter")
            for _ in 0..<100 where seen[label]?.isEmpty != false {
                seen[label] = try await run("cat \(file) 2>/dev/null")
                if seen[label]?.isEmpty != false { try await Task.sleep(for: .milliseconds(100)) }
            }
            _ = try await run("rm -f \(file); \(tmux(label)) kill-server")
        }
        await shell.close()
        func variables(_ env: String?) -> [String: String] {
            Dictionary((env ?? "").split(separator: "\n").map(String.init).compactMap { line -> (String, String)? in
                guard let equals = line.firstIndex(of: "="),
                      ["PATH", "LANG", "LC_ALL", "LC_CTYPE"].contains(String(line[..<equals])) else { return nil }
                return (String(line[..<equals]), String(line[line.index(after: equals)...]))
            }, uniquingKeysWith: { _, last in last })
        }
        let fromClaim = variables(seen[claimed]), fromTyped = variables(seen[typed])
        print("claimed: \(fromClaim)\ntyped:   \(fromTyped)")
        #expect(!fromTyped.isEmpty, "the typed session's shell answered")
        // What matters is what a command finds: the same directories, searched in the same order,
        // and the same locale. Not the same string: a typed session's login profile runs once more
        // and repeats its own entries, and the claim appends `searchPath`'s two directories (D47),
        // which can add a command but never hide one. Compared as the string until 2026-10-24,
        // which failed on the Linux test server over exactly those.
        func directories(_ path: String?) -> [String] {
            var seen = Set<String>()
            return (path ?? "").split(separator: ":").map(String.init).filter { seen.insert($0).inserted }
        }
        let claimedPath = directories(fromClaim["PATH"]), typedPath = directories(fromTyped["PATH"])
        #expect(Array(claimedPath.prefix(typedPath.count)) == typedPath,
                "a claimed session searches the typed one's directories, in its order")
        #expect(Set(claimedPath.dropFirst(typedPath.count)).isSubset(of: ["/opt/homebrew/bin", "/usr/local/bin"]),
                "and adds only the claim's own search path")
        #expect(fromClaim.filter { $0.key != "PATH" } == fromTyped.filter { $0.key != "PATH" },
                "the locale inside a claimed session matches a typed one")
    }

    /// What a shell sends, as it arrives.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ more: Data) { lock.withLock { data.append(more) } }
        var bytes: Data { lock.withLock { data } }
    }

    private final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    /// One control-mode attach over a real SSH shell, as a terminal tab has it: the app's attach
    /// line typed at the shell, `TmuxControlClient` between tmux and a SwiftTerm terminal.
    private final class ControlTab {
        let shell: SSHShellChannel
        var client: TmuxControlClient
        let terminal: Terminal
        private let delegate = Delegate()
        private let output = Collected()
        private var read = 0
        private var reader: Task<Void, Never>?
        var live = false, exited = false

        init(_ shell: SSHShellChannel, columns: Int, rows: Int) {
            self.shell = shell
            client = TmuxControlClient(columns: columns, rows: rows)
            terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: columns, rows: rows, scrollback: 10_000))
            let output = output
            reader = Task { for await chunk in shell.output { if case .stdout(let data) = chunk { output.append(data) } } }
        }

        func apply(_ actions: [TmuxControlAction]) async throws {
            for action in actions {
                switch action {
                case .terminal(let data): terminal.feed(byteArray: Array(data))
                case .transport(let data): try await shell.write(data)
                case .live: live = true
                case .exited: exited = true
                case .showGrid(let columns, let rows, _): terminal.resize(cols: columns, rows: rows)
                }
            }
        }

        /// Reads and draws until `done` holds and output has been quiet a moment, or time runs out.
        @discardableResult
        func pump(seconds: Double = 15, until done: () -> Bool) async throws -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            var quietSince = Date()
            while Date() < deadline {
                let bytes = output.bytes
                if bytes.count > read {
                    let new = bytes[read...]
                    read = bytes.count
                    try await apply(client.receive(Data(new)))
                    quietSince = Date()
                } else if done(), Date().timeIntervalSince(quietSince) > 0.5 {
                    return true
                } else {
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            return done()
        }

        func type(_ text: String) async throws { try await apply(client.input(Data(text.utf8))) }

        var lines: [String] {
            var lines: [String] = []
            var row = 0
            while let line = terminal.getScrollInvariantLine(row: row) {
                lines.append(line.translateToString(trimRight: true))
                row += 1
            }
            return lines
        }

        var screen: [String] { (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) } }

        func detach() async throws {
            // A blank line detaches a control client; the shell was replaced by tmux, so it ends.
            try await shell.write(Data("\n".utf8))
            try await pump(seconds: 5) { exited }
            reader?.cancel()
            await shell.close()
        }
    }

    /// The terminal keeps every line in tmux (D83, control mode): what the session holds is read in as
    /// the app attaches, and every byte printed after reaches the terminal — where tmux attached the
    /// ordinary way skipped what it couldn't draw (route A: 32 of 60 lines printed at once lost).
    @Test func controlModeKeepsEveryLine() async throws {
        guard let transport = try await transport() else { return }
        defer { Task { await transport.close() } }
        guard case .sessions = try await sessions(transport) else {
            Issue.record("the test host has no tmux; these tests need it")
            return
        }
        let version = try await transport.execute(TerminalTmux.versionCommand)
        guard TmuxControlClient.supports(version: version) else {
            print("\(version.trimmingCharacters(in: .whitespacesAndNewlines)) predates control mode's needs: attaches the ordinary way")
            return
        }
        let name = "gpt-live-\(UUID().uuidString.prefix(8))"
        let attach = TerminalTmux.attachLine(name: name, takeOver: false, control: true) + "\n"
        defer { Task { _ = try? await transport.execute(TerminalTmux.killCommand(name: name)) } }

        // A session with a history, then left.
        let first = ControlTab(try await transport.openShell(pty: SSHPTYRequest(columns: 100, rows: 30)), columns: 100, rows: 30)
        try await first.shell.write(Data(attach.utf8))
        #expect(try await first.pump { first.live }, "attached as a control-mode client")
        try await first.type("PS1='$ '; seq 1 150\r")
        try await first.pump { first.screen.contains("150") }
        try await first.detach()
        #expect(first.exited, "tmux said %exit")

        // Back again: read in, then a burst far faster than tmux would draw it.
        let second = ControlTab(try await transport.openShell(pty: SSHPTYRequest(columns: 100, rows: 30)), columns: 100, rows: 30)
        try await second.shell.write(Data(attach.utf8))
        #expect(try await second.pump { second.live }, "attached again")
        try await second.type("seq 1001 3000\r")
        try await second.pump(seconds: 30) { second.screen.contains("3000") }
        let numbers = second.lines.compactMap { Int($0) }
        let expected = Array(1...150) + Array(1001...3000)
        #expect(!second.terminal.isCurrentBufferAlternate, "a shell, on the normal screen")
        #expect(numbers == expected, "every line, in order, once: \(numbers.count) of \(expected.count); missing \(Set(expected).subtracting(numbers).sorted().prefix(10))")
        try await second.detach()
    }
}
