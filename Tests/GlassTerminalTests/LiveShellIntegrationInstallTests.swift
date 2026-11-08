//
//  LiveShellIntegrationInstallTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  Type-ahead's shell integration installed on a real host and taken off again (D102, 2026-11-06), through the
//  installer the app's Settings uses. Gated like the other live tests: the test VM, never a real
//  server. The account's start-up file ends byte for byte as it began.
//

import Foundation
import Testing
import GlassSSHTransport
@testable import GlassTerminal

@MainActor
@Suite("Shell integration on a real host (gated)", .serialized,
       .enabled(if: LiveRemoteEnvironment.isConfigured, "no test host: set GPT_SSH_TEST_HOST, GPT_SSH_TEST_USER and GPT_SSH_TEST_KEY_PATH or GPT_SSH_TEST_PASSWORD"))
struct LiveShellIntegrationInstallTests {
    private func transport() async throws -> SSHTransport {
        let endpoint = SSHEndpoint(host: LiveRemoteEnvironment.host!, port: LiveRemoteEnvironment.port,
                                   username: LiveRemoteEnvironment.user!)
        let hop = SSHHop(displayName: "live shell integration test", endpoint: endpoint, credential: .custom("integration"),
                         options: SSHConnectionOptions(keepAliveInterval: 15))
        let transport = SSHTransport(route: SSHRoute(target: hop), credentials: LiveCredentialResolver(),
                                     trustStore: InMemoryHostTrustStore(), trustDecider: TrustThisRun())
        try await transport.connect()
        return transport
    }

    /// What a new login shell prints for `command`, through a PTY as a terminal sees it.
    private func loginShellOutput(_ transport: SSHTransport, typing command: String) async throws -> String {
        let shell = try await transport.openShell(pty: SSHPTYRequest(columns: 100, rows: 30))
        try await shell.sendCommand(command)
        try await shell.sendCommand("exit")
        var collected = Data()
        for await chunk in shell.output { if case .stdout(let data) = chunk { collected.append(data) } }
        return String(decoding: collected, as: UTF8.self)
    }

    private func remote(_ transport: SSHTransport) -> TerminalShellIntegrationInstaller.Remote {
        TerminalShellIntegrationInstaller.Remote(
            serverID: UUID(),
            run: { try await transport.execute($0) },
            openClient: {
                let session = try await transport.openSFTP()
                return SFTPClient(session: session, extensions: await session.serverExtensions)
            })
    }

    /// The file's bytes as the host has them (`od` of nothing for a missing file is "missing").
    private func bytes(_ transport: SSHTransport, _ path: String) async throws -> String {
        try await transport.execute("if [ -e \"$HOME/\(path)\" ]; then od -An -tx1 -v \"$HOME/\(path)\" | tr -d ' \\n'; else printf missing; fi")
    }

    /// "No surprises for users" (the owner, 2026-11-06): something appended to the start-up file after the install,
    /// as `echo … >> ~/.bashrc` appends, is a line of its own (not inside the app's comment), and removing the
    /// integration keeps it.
    @Test("a line appended after the install stays a line of its own, and removing the integration keeps it")
    func appendedLater() async throws {
        let transport = try await transport()
        defer { Task { await transport.close() } }
        let remote = remote(transport)
        let shell = try #require(await TerminalShellIntegrationInstaller.shell(of: remote).kind)
        let rcPath = TerminalShellIntegration.rcPath(for: shell)
        let original = try await bytes(transport, rcPath)
        guard case .notInstalled = await TerminalShellIntegrationInstaller.state(of: remote) else {
            Issue.record("the test host already has it installed; remove it first")
            return
        }
        try await TerminalShellIntegrationInstaller.install(on: remote)
        _ = try await transport.execute("printf '%s\\n' 'echo appended-later-$((6*7))' >> \"$HOME/\(rcPath)\"")
        let ran = try await loginShellOutput(transport, typing: "true")
        #expect(ran.contains("appended-later-42") && !ran.contains("not found"), "the appended line ran at login: \(ran.suffix(300))")
        try await TerminalShellIntegrationInstaller.remove(from: remote)
        let client = try await remote.openClient()
        let after = await TerminalShellIntegrationInstaller.read(rcPath, through: client) ?? ""
        try? await client.close()
        #expect(after.hasSuffix("\necho appended-later-$((6*7))\n"), "kept, on its own line: \(after.suffix(80).debugDescription)")
        #expect(!after.contains(TerminalShellIntegration.marker))
        // Back as it began: the test's own restore, then checked byte for byte.
        _ = try await transport.execute("f=\"$HOME/\(rcPath)\"; head -c \(original == "missing" ? 0 : original.count / 2) \"$f\" > \"$f.gpt-restore\" && cat \"$f.gpt-restore\" > \"$f\" && rm \"$f.gpt-restore\"")
        if original == "missing" { _ = try await transport.execute("rm -f \"$HOME/\(rcPath)\"") }
        #expect(try await bytes(transport, rcPath) == original, "restored byte for byte")
    }

    /// A start-up file kept in a dotfiles folder and linked from home: the file it links to is changed, the link stays.
    @Test("a linked start-up file is changed where it lives; the link stays a link")
    func linkedStartupFile() async throws {
        let transport = try await transport()
        defer { Task { await transport.close() } }
        let remote = remote(transport)
        let shell = try #require(await TerminalShellIntegrationInstaller.shell(of: remote).kind)
        let rcPath = TerminalShellIntegration.rcPath(for: shell)
        let original = try await bytes(transport, rcPath)
        try #require(original != "missing", "the test host's start-up file")
        guard case .notInstalled = await TerminalShellIntegrationInstaller.state(of: remote) else {
            Issue.record("the test host already has it installed; remove it first")
            return
        }
        let folder = ".gpt-dotfiles-test"
        _ = try await transport.execute("mkdir -p \"$HOME/\(folder)\" && mv \"$HOME/\(rcPath)\" \"$HOME/\(folder)/rc\" && ln -s \"$HOME/\(folder)/rc\" \"$HOME/\(rcPath)\"")
        do {
            let client = try await remote.openClient()
            let before = await TerminalShellIntegrationInstaller.read(rcPath, through: client)
            try await TerminalShellIntegrationInstaller.install(on: remote)
            #expect(try await transport.execute("test -L \"$HOME/\(rcPath)\" && echo link") == "link\n", "still a link")
            #expect(await TerminalShellIntegrationInstaller.read("\(folder)/rc", through: client)
                    == TerminalShellIntegration.addingSourceLine(to: before, shell: shell), "the line added to the linked file")
            try await TerminalShellIntegrationInstaller.remove(from: remote)
            #expect(try await transport.execute("test -L \"$HOME/\(rcPath)\" && echo link") == "link\n", "still a link after removal")
            #expect(try await bytes(transport, "\(folder)/rc") == original, "the linked file as it was")
            try? await client.close()
        } catch {
            Issue.record("\(error)")
        }
        _ = try await transport.execute("rm \"$HOME/\(rcPath)\" && mv \"$HOME/\(folder)/rc\" \"$HOME/\(rcPath)\" && rmdir \"$HOME/\(folder)\"")
        #expect(try await bytes(transport, rcPath) == original, "restored byte for byte")
    }

    @Test("installed: one line added and the script written, and a new shell marks its prompt; removed: as it was")
    func installAndRemove() async throws {
        let transport = try await transport()
        defer { Task { await transport.close() } }
        let remote = remote(transport)
        let shell = try #require(await TerminalShellIntegrationInstaller.shell(of: remote).kind, "the account's shell")
        let rcPath = TerminalShellIntegration.rcPath(for: shell)
        let scriptPath = TerminalShellIntegration.remoteScriptPath(for: shell)
        let client = try await remote.openClient()
        defer { Task { try? await client.close() } }
        let before = await TerminalShellIntegrationInstaller.read(rcPath, through: client)
        let originalBytes = try await bytes(transport, rcPath)
        guard case .notInstalled = await TerminalShellIntegrationInstaller.state(of: remote) else {
            Issue.record("the test host already has it installed; remove it first")
            return
        }

        try await TerminalShellIntegrationInstaller.install(on: remote)
        #expect(await TerminalShellIntegrationInstaller.state(of: remote) == .installed(shell))
        let added = try await bytes(transport, rcPath)
        #expect(originalBytes == "missing" || added.hasPrefix(originalBytes), "only added to: what was there is untouched")
        let installed = await TerminalShellIntegrationInstaller.read(rcPath, through: client)
        #expect(installed == TerminalShellIntegration.addingSourceLine(to: before, shell: shell), "one line added, nothing else")
        #expect(await TerminalShellIntegrationInstaller.read(scriptPath, through: client) == TerminalShellIntegration.script(for: shell))
        // Installing again changes nothing.
        try await TerminalShellIntegrationInstaller.install(on: remote)
        #expect(await TerminalShellIntegrationInstaller.read(rcPath, through: client) == installed)

        let marked = try await loginShellOutput(transport, typing: "echo marked-$((6*7))")
        #expect(marked.contains("\u{1B}]133;A") && marked.contains("\u{1B}]133;B"), "a new shell marks its prompt")
        #expect(marked.contains("\u{1B}]633;E;echo marked-$((6*7))"), "and says each command as typed")
        #expect(marked.contains("\u{1B}]133;D;0"))

        try await TerminalShellIntegrationInstaller.remove(from: remote)
        let after = await TerminalShellIntegrationInstaller.read(rcPath, through: client)
        #expect(after == before, "the start-up file as it was")
        #expect(try await bytes(transport, rcPath) == originalBytes, "byte for byte (and gone again if the install made it)")
        #expect(await TerminalShellIntegrationInstaller.read(scriptPath, through: client) == nil, "the script gone")
        #expect((try? await client.getAttributes(at: (scriptPath as NSString).deletingLastPathComponent)) == nil,
                "the app's folder gone, emptied")
        guard case .notInstalled = await TerminalShellIntegrationInstaller.state(of: remote) else {
            Issue.record("still reads as installed")
            return
        }
        let unmarked = try await loginShellOutput(transport, typing: "echo plain")
        #expect(!unmarked.contains("\u{1B}]133;"), "a new shell no longer marks anything")
    }
}
