#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// This Mac's tmux server under launchd (2026-10-12): a Force Quit of an app started inside a
/// session ended every local terminal, since a server an app starts is that app's to end.
@Suite("Local tmux under launchd", .serialized)
struct MacTmuxServiceTests {
    @Test("the job runs tmux in the foreground at a terminal's priority, with the pane's environment less launchd's own")
    func job() throws {
        let job = MacTmuxService.job(tmux: "/opt/homebrew/bin/tmux",
                                     environment: ["PATH": "/opt/homebrew/bin:/usr/bin", "LANG": "en_US.UTF-8",
                                                   "SSH_AUTH_SOCK": "/private/tmp/stale", "TMPDIR": "/var/folders/stale"])
        #expect(job["Label"] as? String == "com.glasspowertools.tmux")
        #expect(job["ProgramArguments"] as? [String] == ["/opt/homebrew/bin/tmux", "-u", "-D"])
        #expect(job["EnvironmentVariables"] as? [String: String] == ["PATH": "/opt/homebrew/bin:/usr/bin", "LANG": "en_US.UTF-8"],
                "the agent socket and temporary folder are launchd's, current for this login")
        #expect(job["ProcessType"] as? String == "Interactive" && job["KeepAlive"] as? Bool == false)
        #expect(job["RunAtLoad"] as? Bool == true && job["AbandonProcessGroup"] as? Bool == true)
        #expect(MacTmuxService.jobURL()?.path.contains("/Library/LaunchAgents/") == false, "no login item")
        let test = MacTmuxService.job(label: "t", tmux: "tmux", environment: [:], serverArguments: ["-S", "/tmp/s"])
        #expect(test["ProgramArguments"] as? [String] == ["tmux", "-S", "/tmp/s", "-u", "-D"])
    }

    private final class Calls: @unchecked Sendable {
        let lock = NSLock()
        var list: [[String]] = []
        var serverAnswersAfter = Int.max
        var bootstrapFails = false
        func run(_ executable: String, _ arguments: [String]) -> String? {
            lock.withLock {
                list.append([executable] + arguments)
                if arguments.contains("-N") {
                    serverAnswersAfter -= 1
                    return serverAnswersAfter < 0 ? "" : nil
                }
                if arguments.first == "bootstrap" { return bootstrapFails ? nil : "" }
                return nil
            }
        }
    }

    @Test("a running server is left alone; none is started under launchd, which is asked to drop a stale job first")
    func ensure() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gpt-tmuxjob-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let jobURL = folder.appendingPathComponent("job.plist")

        let running = Calls()
        running.serverAnswersAfter = 0
        #expect(MacTmuxService.ensureServer(tmux: "tmux", environment: [:], jobURL: jobURL, run: running.run, wait: { _ in }) == .alreadyRunning)
        #expect(running.list == [["tmux", "-N", "list-sessions"]])
        #expect(!FileManager.default.fileExists(atPath: jobURL.path), "nothing written")

        let starting = Calls()
        starting.serverAnswersAfter = 3
        #expect(MacTmuxService.ensureServer(tmux: "tmux", environment: ["LANG": "C"], jobURL: jobURL, run: starting.run, wait: { _ in }) == .started)
        let launchctl = starting.list.filter { $0.first == "/bin/launchctl" }.map { Array($0.dropFirst()) }
        #expect(launchctl.map(\.first) == ["bootout", "bootstrap"], "out first, so the new environment runs")
        #expect(launchctl.last?.last == jobURL.path)
        let written = try #require(NSDictionary(contentsOf: jobURL) as? [String: Any])
        #expect(written["EnvironmentVariables"] as? [String: String] == ["LANG": "C"])

        let refused = Calls()
        refused.bootstrapFails = true
        #expect(MacTmuxService.ensureServer(tmux: "tmux", environment: [:], jobURL: jobURL, run: refused.run, wait: { _ in }) == .couldNotStart,
                "the claim then starts tmux itself, as before")

        let silent = Calls()
        var waited: Duration = .zero
        #expect(MacTmuxService.ensureServer(tmux: "tmux", environment: [:], jobURL: jobURL, run: silent.run, wait: { waited += $0 }) == .couldNotStart)
        #expect(waited >= MacTmuxService.startTimeout)
    }

    nonisolated static var tmux: String? { MacLocalTmux.executablePath() }

    /// The real thing on a private server: a socket of its own, no configuration, a label of its own,
    /// and the job file in a temporary folder — neither the owner's server nor his job is touched.
    @Test("launchd runs a private tmux server, not this process: its parent is launchd, and it outlives its sessions' clients",
          .enabled(if: MacTmuxServiceTests.tmux != nil))
    func live() throws {
        let tmux = try #require(Self.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-tmuxjob-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let socket = folder.appendingPathComponent("s").path
        let server = ["-S", socket, "-f", "/dev/null"]
        let label = "com.glasspowertools.tmux.test.\(UUID().uuidString.prefix(8))"
        let jobURL = folder.appendingPathComponent("job.plist")
        defer {
            MacTmuxService.remove(label: label, jobURL: jobURL)
            _ = MacLocalTmux.run(tmux, server + ["kill-server"])
            try? FileManager.default.removeItem(at: folder)
        }
        #expect(!MacTmuxService.serverRunning(tmux: tmux, serverArguments: server))
        let outcome = MacTmuxService.ensureServer(tmux: tmux, environment: ["PATH": "/usr/bin:/bin", "TMUX_TMPDIR": folder.path],
                                                  label: label, serverArguments: server, jobURL: jobURL)
        #expect(outcome == .started)
        // The server's parent is launchd, and its process group is its own, not this test's.
        let pids = (MacLocalTmux.run("/usr/bin/pgrep", ["-f", socket]) ?? "").split(separator: "\n").compactMap { Int32($0) }
        let serverPID = try #require(pids.first)
        let info = (MacLocalTmux.run("/bin/ps", ["-o", "ppid=,pgid=", "-p", String(serverPID)]) ?? "")
            .split(separator: " ").compactMap { Int32($0) }
        #expect(info.first == 1, "launchd's: \(info)")
        #expect(info.last != getpgrp())
        #expect(MacLocalTmux.run(tmux, server + ["new-session", "-d", "-s", "probe", "/bin/sleep", "600"]) != nil)
        #expect(MacTmuxService.ensureServer(tmux: tmux, environment: [:], label: label, serverArguments: server, jobURL: jobURL) == .alreadyRunning)
        // Taken away, the job's server ends with it.
        MacTmuxService.remove(label: label, jobURL: jobURL)
        var gone = false
        for _ in 0..<40 where !gone {
            gone = !MacTmuxService.serverRunning(tmux: tmux, serverArguments: server)
            if !gone { Thread.sleep(forTimeInterval: 0.05) }
        }
        #expect(gone)
    }
}
#endif
