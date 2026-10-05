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
import GlassSSHTransport
@testable import GlassTerminal

@Suite("tmux against a real host (gated)", .serialized)
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
}
