//
//  LivePathPreviewTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A path an SSH terminal printed, found on its host as Quick Look and the pointer's preview find it
//  (`TerminalSession.locate`), against a real host. Gated like the other live tests (NOT RUN when
//  unconfigured). The session's commands go over a real connection; it makes a folder of its own in
//  /tmp and removes it.
//

import Foundation
import Testing
import GlassSSHTransport
@testable import GlassTerminal

@Suite("A printed path found on a real host (gated)", .serialized, .enabled(if: LiveRemoteEnvironment.isConfigured, "no test host: set GPT_SSH_TEST_HOST, GPT_SSH_TEST_USER and GPT_SSH_TEST_KEY_PATH or GPT_SSH_TEST_PASSWORD"))
@MainActor
struct LivePathPreviewTests {
    private func transport() async throws -> SSHTransport? {
        guard LiveRemoteEnvironment.isConfigured else {
            print("NOT RUN: set GPT_SSH_TEST_HOST, GPT_SSH_TEST_USER and GPT_SSH_TEST_KEY_PATH")
            return nil
        }
        let endpoint = SSHEndpoint(host: LiveRemoteEnvironment.host!, port: LiveRemoteEnvironment.port,
                                   username: LiveRemoteEnvironment.user!)
        let hop = SSHHop(displayName: "live path test", endpoint: endpoint, credential: .custom("integration"),
                         options: SSHConnectionOptions(keepAliveInterval: 15))
        let transport = SSHTransport(route: SSHRoute(target: hop), credentials: LiveCredentialResolver(),
                                     trustStore: InMemoryHostTrustStore(), trustDecider: TrustThisRun())
        try await transport.connect()
        return transport
    }

    @Test("absolute, in the home folder, and relative to a tmux session's folder")
    func locatesPrintedPaths() async throws {
        guard let transport = try await transport() else { return }
        let root = "/tmp/glass-path-live-\(UUID().uuidString.prefix(8))"
        let home = try await transport.execute("printf '%s' \"$HOME\"")
        let homeFolder = "glass-path-live-\(UUID().uuidString.prefix(8))"
        _ = try await transport.execute("mkdir -p \(root)/docs && printf '# Notes\\n' > \(root)/docs/README.md && mkdir -p ~/\(homeFolder) && printf 'x' > ~/\(homeFolder)/a.txt")
        let tmuxName = "gpt-path-\(UUID().uuidString.prefix(8))"
        func cleanUp() async {
            _ = try? await transport.execute("rm -rf \(root) ~/\(homeFolder); tmux kill-session -t =\(tmuxName) 2>/dev/null; true")
            await transport.close()
        }

        let session = TerminalSession(server: ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann"))
        session.tmuxCommandRunner = { command in try await transport.execute(command) }

        let file = await session.locate("\(root)/docs/README.md")
        #expect(file?.path == "\(root)/docs/README.md" && file?.isDirectory == false, "an absolute file: \(String(describing: file))")
        let folder = await session.locate("\(root)/docs")
        #expect(folder?.isDirectory == true, "an absolute folder: \(String(describing: folder))")
        #expect(await session.locate("\(root)/missing.md") == nil, "a path that isn't there")
        let inHome = await session.locate("~/\(homeFolder)/a.txt")
        #expect(inHome?.path == "\(home)/\(homeFolder)/a.txt", "a file in the home folder: \(String(describing: inHome))")

        // Relative: against the folder the terminal's tmux session is in.
        let hasTmux = (try? await transport.execute("command -v tmux >/dev/null && echo yes"))?.contains("yes") == true
        if hasTmux {
            // A moment for the session's shell to start: tmux reads the folder from it.
            _ = try await transport.execute("tmux new-session -d -s \(tmuxName) -c \(root); sleep 1")
            session.tmuxSessionName = tmuxName
            let relative = await session.locate("docs/README.md")
            #expect(relative?.path == "\(root)/docs/README.md", "relative to the tmux session's folder: \(String(describing: relative))")
        } else {
            print("tmux is not installed on the test host: relative paths in tmux not checked")
        }
        await cleanUp()
    }
}
